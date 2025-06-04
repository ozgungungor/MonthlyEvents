import SwiftUI
import UserNotifications
import EventKit

struct MainView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) var currentLocale // Mevcut locale'i al

    @StateObject private var dataManager = CardDataManager.shared
    @StateObject private var holidayService = HolidayService.shared

    @State private var showingAddCardSheet = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var openedCardID: String? = nil
    @State private var showingSettingsSheet = false

    @State private var navigationViewID = UUID() // 👈 NavigationView’i yeniden oluşturmak için ID

    private var basePermissionMessageText: String { NSLocalizedString("PERMISSION_ALERT_BASE_MESSAGE", comment: "") }
    private var permMsgNotificationsDeniedDetail: String { NSLocalizedString("PERM_MSG_NOTIF_DENIED_DETAIL", comment: "") }
    private var permMsgNotificationsNotDeterminedDetail: String { NSLocalizedString("PERM_MSG_NOTIF_NOT_DETERMINED_DETAIL", comment: "") }
    private var permMsgCalendarDeniedDetailFullAccess: String { NSLocalizedString("PERM_MSG_CALENDAR_DENIED_DETAIL_FULL_ACCESS", comment: "") }
    private var permMsgCalendarNotObtainedFullAccess: String { NSLocalizedString("PERM_MSG_CALENDAR_NOT_OBTAINED_FULL_ACCESS", comment: "") }
    private var manageInSettingsText: String { NSLocalizedString("PERMISSION_ALERT_MANAGE_IN_SETTINGS", comment: "") }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                if dataManager.cards.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                            .font(.system(size: 70))
                            .foregroundColor(.gray.opacity(0.7))
                        Text(LocalizedStringKey("EMPTY_STATE_TITLE"))
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(LocalizedStringKey("EMPTY_STATE_MESSAGE"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button(LocalizedStringKey("EMPTY_STATE_ADD_CARD_BUTTON")) {
                            showingAddCardSheet = true
                        }
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding()
                } else {
                    List {
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

                        ForEach(dataManager.cards) { card in
                            NavigationLink(
                                destination: CardFormView(dataManager: dataManager, holidayService: holidayService, cardToEdit: card),
                                tag: card.id.uuidString,
                                selection: $openedCardID
                            ) {
                                CardRowView(card: card, holidayService: holidayService)
                            }
                        }
                        .onDelete(perform: dataManager.deleteCard)
                    }
                    .listStyle(.insetGrouped)
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(LocalizedStringKey("MY_CARDS_TITLE"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showingAddCardSheet = true } label: {
                            Label(LocalizedStringKey("ADD_CARD_ACCESSIBILITY_LABEL"), systemImage: "plus.circle.fill")
                        }
                        Button { showingSettingsSheet = true } label: {
                            Label(LocalizedStringKey("SETTINGS_GEAR_ACCESSIBILITY_LABEL"), systemImage: "gearshape.fill")
                        }
                    }
                    .font(.title2)
                }
            }
            .sheet(isPresented: $showingAddCardSheet) {
                CardFormView(dataManager: dataManager, holidayService: holidayService)
            }
            .sheet(isPresented: $showingSettingsSheet) {
                SettingsView()
            }
            .alert(LocalizedStringKey("ALERT_PERMISSION_REQUIRED_TITLE"), isPresented: $showingPermissionAlert) {
                Button(LocalizedStringKey("ALERT_BUTTON_GO_TO_SETTINGS")) {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                Button(LocalizedStringKey("ALERT_BUTTON_OK"), role: .cancel) {}
            } message: {
                Text(permissionAlertMessage)
            }
            .task {
                UIApplication.shared.applicationIconBadgeNumber = 0
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                await checkAndRequestPermissions()
                await rescheduleAllNotifications()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    UIApplication.shared.applicationIconBadgeNumber = 0
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    holidayService.refresh()
                    Task {
                        await rescheduleAllNotifications()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCard"))) { notification in
                if let cardID = notification.object as? String {
                    openedCardID = cardID
                }
            }
        }
        .id(navigationViewID) // 👈 View yeniden oluşturulsun
        .onChange(of: currentLocale) { _ in
            holidayService.refresh()
            Task {
                await rescheduleAllNotifications()
                await checkAndRequestPermissions()
            }
            navigationViewID = UUID() // 👈 NavigationView’i sıfırla
        }
    }

    private func checkAndRequestPermissions() async {
        let _ = await NotificationManager.shared.requestPermission()
        await holidayService.requestCalendarAccess()

        var messagesForAlert: [String] = []

        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        if notificationSettings.authorizationStatus == .denied {
            messagesForAlert.append("• \(permMsgNotificationsDeniedDetail)")
        } else if notificationSettings.authorizationStatus == .notDetermined {
            messagesForAlert.append("• \(permMsgNotificationsNotDeterminedDetail)")
        }

        if !holidayService.hasCalendarAccess {
            let calendarStatus = EKEventStore.authorizationStatus(for: .event)
            if #available(iOS 17.0, *) {
                if calendarStatus == .denied || calendarStatus == .restricted || calendarStatus == .writeOnly {
                    messagesForAlert.append("• \(permMsgCalendarDeniedDetailFullAccess)")
                } else {
                    messagesForAlert.append("• \(permMsgCalendarNotObtainedFullAccess)")
                }
            } else {
                messagesForAlert.append("• \(permMsgCalendarDeniedDetailFullAccess)")
            }
        }

        if !messagesForAlert.isEmpty {
            await MainActor.run {
                self.permissionAlertMessage = "\(basePermissionMessageText)\n\n" +
                                              messagesForAlert.joined(separator: "\n\n") +
                                              "\n\n\(manageInSettingsText)"
                self.showingPermissionAlert = true
            }
        }
    }

    private func rescheduleAllNotifications() async {
        let today = Date()
        for card in dataManager.cards {
            let dueDates = DueDateCalculator.calculateDueDates(for: card, referenceDate: today, using: holidayService)
            NotificationManager.shared.removeReminders(for: card)
            for (index, dueDate) in dueDates.enumerated() {
                let suffix = index == 0 ? "thisMonth" : (index == 1 ? "nextMonth" : "futureMonth\(index+1)")
                NotificationManager.shared.scheduleReminder(for: card, dueDate: dueDate, idSuffix: suffix)
            }
        }
    }
}
