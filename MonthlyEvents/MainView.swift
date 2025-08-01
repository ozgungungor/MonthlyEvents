import SwiftUI
import UserNotifications
import EventKit
import AppTrackingTransparency
import AdSupport

struct MainView: View {
    // MARK: - Properties
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) var currentLocale

    @StateObject private var dataManager = CardDataManager.shared
    @StateObject private var holidayService = HolidayService.shared

    @State private var showingAddCardSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var openedCardID: String? = nil

    @State private var navigationViewID = UUID()

    // MARK: - Computed Properties
    private var activeCards: [CreditCard] {
        dataManager.cards.filter { !$0.isDeleted }
    }

    private var groupedCards: [(PaymentType, [CreditCard])] {
        let grouped = Dictionary(grouping: activeCards, by: { $0.type })
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    // MARK: - Body
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                if activeCards.isEmpty {
                    emptyStateView
                } else {
                    cardListView
                }
            }
            .navigationTitle(LocalizedStringKey("MY_CARDS_TITLE"))
            .toolbar { mainToolbar }
            .sheet(isPresented: $showingAddCardSheet) {
                CardFormView(dataManager: dataManager, holidayService: holidayService)
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
            .alert(LocalizedStringKey("ALERT_PERMISSION_REQUIRED_TITLE"), isPresented: $showingPermissionAlert) {
                permissionAlertButtons
            } message: {
                Text(permissionAlertMessage)
            }
            .onAppear(perform: onInitialLoad)
            .onChange(of: scenePhase, perform: handleScenePhaseChange)
            .onChange(of: currentLocale) { newLocale in
                handleLocaleChange(newLocale: newLocale)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openCardNotification)) { handleOpenCardNotification($0) }
        }
        .id(navigationViewID)
    }
}

// MARK: - Subviews
private extension MainView {
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.7))
            
            Text(LocalizedStringKey("EMPTY_STATE_TITLE_ITEM"))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(LocalizedStringKey("EMPTY_STATE_MESSAGE_ITEM"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(LocalizedStringKey("EMPTY_STATE_ADD_ITEM_BUTTON")) {
                showingAddCardSheet = true
            }
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
    
    var cardListView: some View {
        List {
            calendarAccessStatusSection
            
            ForEach(groupedCards, id: \.0) { type, cardsInGroup in
                Section(header: Text(type.groupHeader)) {
                    ForEach(cardsInGroup) { card in
                        NavigationLink(
                            destination: CardFormView(dataManager: dataManager, holidayService: holidayService, cardToEdit: card),
                            tag: card.id.uuidString,
                            selection: $openedCardID
                        ) {
                            CardRowView(card: card, holidayService: holidayService)
                        }
                    }
                    .onDelete { indexSet in
                        let cardsToDelete = indexSet.map { cardsInGroup[$0] }
                        for card in cardsToDelete {
                            dataManager.delete(card: card)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.clear)
        .scrollContentBackground(.hidden)
    }

    var calendarAccessStatusSection: some View {
        Section {
            HStack {
                Image(systemName: holidayService.hasCalendarAccess ? "calendar.circle.fill" : "calendar.circle")
                    .foregroundColor(holidayService.hasCalendarAccess ? .green : .orange)
                Text(holidayService.hasCalendarAccess ?
                    LocalizedStringKey("CALENDAR_ACCESS_GRANTED") :
                    LocalizedStringKey("CALENDAR_ACCESS_DENIED"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                Button { showingAddCardSheet = true } label: {
                    Label(LocalizedStringKey("ADD_ITEM_ACCESSIBILITY_LABEL"), systemImage: "plus.circle.fill")
                }
                Button { showingSettingsSheet = true } label: {
                    Label(LocalizedStringKey("SETTINGS_GEAR_ACCESSIBILITY_LABEL"), systemImage: "gearshape.fill")
                }
            }
            .font(.title2)
        }
    }
    
    @ViewBuilder
    var permissionAlertButtons: some View {
        Button(LocalizedStringKey("ALERT_BUTTON_GO_TO_SETTINGS")) {
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        }
        Button(LocalizedStringKey("ALERT_BUTTON_OK"), role: .cancel) {}
    }
}

// MARK: - Methods & Event Handlers
private extension MainView {

    func onInitialLoad() {
        dataManager.updateInstallmentsAndSubscriptions()
        holidayService.refresh()
        UIApplication.shared.applicationIconBadgeNumber = 0
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        NotificationManager.shared.updateAppBadgeCount()
        
        requestAppTrackingPermissionIfNeeded()
    }
    
    func handleScenePhaseChange(newPhase: ScenePhase) {
        if newPhase == .active {
            // Uygulama tekrar aktif olduğunda bekleyen işlemleri senkronize et
            dataManager.synchronizePendingDeletions()
            onInitialLoad()
            CalendarManager.shared.resetAndCreateNewCalendar(for: currentLocale)
            holidayService.refresh()
            rescheduleAllEventsAndNotifications(for: currentLocale)
            NotificationManager.shared.updateAppBadgeCount()
        }
    }
    
    func handleLocaleChange(newLocale: Locale) {
        navigationViewID = UUID()
        
        Task {
            CalendarManager.shared.resetAndCreateNewCalendar(for: newLocale)
            holidayService.refresh()
            rescheduleAllEventsAndNotifications(for: newLocale)
        }
    }
    
    private func rescheduleAllEventsAndNotifications(for locale: Locale) {
        Task {
            let hasCalendarAccess = await CalendarManager.shared.requestAccessIfNeeded()
            let hasNotificationAccess = await NotificationManager.shared.requestPermission()
            
            // Sadece aktif ve silinmemiş kartları kullan
            for card in activeCards {
                let dueDates = DueDateCalculator.calculateDueDates(for: card, using: holidayService)
                
                if hasCalendarAccess {
                    CalendarManager.shared.addOrUpdateEvents(for: card, dueDates: dueDates, holidayService: holidayService, locale: locale)
                }
                
                if hasNotificationAccess {
                    NotificationManager.shared.scheduleReminders(for: card, dueDates: dueDates, locale: locale)
                }
            }
        }
    }
    
    func handleOpenCardNotification(_ notification: Notification) {
        if let cardID = notification.userInfo?["cardID"] as? String {
            openedCardID = cardID
        }
    }

    func requestAppTrackingPermissionIfNeeded() {
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { status in
                switch status {
                case .authorized:
                    print("✅ Kullanıcı takip izni verdi")
                case .denied:
                    print("❌ Kullanıcı takip iznini reddetti")
                case .notDetermined:
                    print("❓ Kullanıcı henüz karar vermedi")
                case .restricted:
                    print("⚠️ Kısıtlanmış")
                @unknown default:
                    break
                }
            }
        }
    }
}

extension Notification.Name {
    static let openCardNotification = Notification.Name("OpenCard")
}
