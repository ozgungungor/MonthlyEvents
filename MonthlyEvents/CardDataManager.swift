import SwiftUI
import Foundation

class CardDataManager: ObservableObject {
    static let shared = CardDataManager()
    @Published var cards: [CreditCard] = []
    private let cardsKey = "SavedCreditCards"

    private init() {
        loadCards()
        // Uygulama her açıldığında veya aktif olduğunda bekleyen işlemleri senkronize et.
        synchronizeWithCloudKit()
    }
    
    // MARK: - Senkronizasyon Mantığı

    private func synchronizeWithCloudKit() {
        // Önce bekleyen silme işlemlerini gönder
        synchronizePendingDeletions()
        
        Task {
            // Aktif (silinmemiş) kartları kontrol et
            let activeCards = self.cards.filter { !$0.isDeleted }
            
            // Eğer aktif yerel kart yoksa, CloudKit'ten veri çek.
            if activeCards.isEmpty {
                print("Aktif yerel kart yok. CloudKit'ten veri çekiliyor...")
                let fetchedCards = await CloudKitManager.shared.fetchCards()
                
                await MainActor.run {
                    self.cards = fetchedCards
                    self.saveCards()
                    self.rescheduleAllEventsAndNotifications()
                    print("Veriler CloudKit'ten yenilendi.")
                }
            }
            // Eğer yerel depolamada veri varsa, CloudKit'in durumunu kontrol et.
            else {
                let cloudHasRecords = await CloudKitManager.shared.hasRecords()
                
                // Eğer CloudKit boşsa, yerel verileri CloudKit'e yükle.
                if !cloudHasRecords {
                    print("Lokalde veri var ama CloudKit boş. Lokal veriler CloudKit'e aktarılıyor...")
                    for card in activeCards { // Sadece aktif kartları gönder
                        CloudKitManager.shared.save(card: card)
                    }
                } else {
                    print("Hem lokalde hem de CloudKit'te veri mevcut. Senkronizasyon tamamlandı.")
                }
            }
        }
    }
    
    /// Beklemedeki silme işlemlerini CloudKit ile senkronize eder.
    func synchronizePendingDeletions() {
        let pendingDeletions = cards.filter { $0.isDeleted }
        guard !pendingDeletions.isEmpty else { return }
        
        print("\(pendingDeletions.count) adet bekleyen silme işlemi senkronize ediliyor...")
        
        for cardToDelete in pendingDeletions {
            CloudKitManager.shared.delete(cardID: cardToDelete.id) { [weak self] success in
                if success {
                    DispatchQueue.main.async {
                        self?.purgeDeletedCard(withId: cardToDelete.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Veri Yönetimi

    private func loadCards() {
        if let data = UserDefaults.standard.data(forKey: cardsKey) {
            if let decodedCards = try? JSONDecoder().decode([CreditCard].self, from: data) {
                self.cards = decodedCards
            }
        }
    }

    private func saveCards() {
        if let encoded = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(encoded, forKey: cardsKey)
        }
    }
    
    // MARK: - Public API
    
    func addCard(_ card: CreditCard) {
        cards.append(card)
        saveCards()
        CloudKitManager.shared.save(card: card)
        rescheduleAllEventsAndNotifications()
        forceReload()
    }

    func updateCard(_ card: CreditCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
        saveCards()
        CloudKitManager.shared.update(card: card)
        rescheduleAllEventsAndNotifications()
        forceReload()
    }
    
    // MARK: - Silme Mantığı
    
    func delete(card: CreditCard) {
        performSoftDeletion(for: card)
    }

    func delete(in group: [CreditCard], at offsets: IndexSet) {
        let cardsToDelete = offsets.map { group[$0] }
        for card in cardsToDelete {
            performSoftDeletion(for: card)
        }
    }
    
    private func performSoftDeletion(for card: CreditCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        
        cards[index].isDeleted = true
        print("Kart (\(card.name)) yerel olarak silinmek üzere işaretlendi.")
        saveCards()
        synchronizePendingDeletions()
        forceReload()
    }
    
    private func purgeDeletedCard(withId cardID: UUID) {
        print("Kart (\(cardID)) sunucudan silindi, yerelden kalıcı olarak temizleniyor.")
        cards.removeAll(where: { $0.id == cardID })
        saveCards()
        forceReload()
    }
    
    // MARK: - Central Rescheduling Logic
    
    func rescheduleAllEventsAndNotifications() {
        Task {
            let hasCalendarAccess = await CalendarManager.shared.requestAccessIfNeeded()
            let hasNotificationAccess = await NotificationManager.shared.requestPermission()
            
            let languageIdentifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.current.identifier
            let locale = Locale(identifier: languageIdentifier)
            
            if hasCalendarAccess {
                CalendarManager.shared.resetAndCreateNewCalendar(for: locale)
            }
            if hasNotificationAccess {
                NotificationManager.shared.removeAllScheduledNotifications()
            }
            
            let holidayService = HolidayService.shared

            for card in cards where card.isActive && !card.isDeleted { // Sadece aktif ve silinmemiş kartlar
                let dueDates = DueDateCalculator.calculateDueDates(for: card, using: holidayService)
                
                if hasCalendarAccess {
                    CalendarManager.shared.addOrUpdateEvents(for: card, dueDates: dueDates, holidayService: holidayService, locale: locale)
                }
                
                if hasNotificationAccess {
                    NotificationManager.shared.scheduleReminders(for: card, dueDates: dueDates, locale: locale)
                }
            }
            print("Takvim ve bildirimler 'hard reset' yöntemiyle yeniden planlandı.")
        }
    }
    
    // MARK: - Other Functions
    
    func updateInstallmentsAndSubscriptions() {
        var needsSave = false
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let updatedCards = cards.map { card -> CreditCard in
            var mutableCard = card
            
            if mutableCard.type == .loan,
               let creationDate = mutableCard.creationDate,
               let totalInstallments = mutableCard.totalInstallments {
                
                var paymentsMade = 0
                var dateCursor = creationDate
                
                var initialLoanCheckDateComponents = calendar.dateComponents([.year, .month], from: creationDate)
                initialLoanCheckDateComponents.day = mutableCard.dueDate
                guard let loanStartPaymentDate = calendar.date(from: initialLoanCheckDateComponents) else { return card }

                if creationDate <= loanStartPaymentDate {
                    paymentsMade = 0
                } else {
                    paymentsMade = 0
                }

                while dateCursor < today {
                    var dueDateComponents = calendar.dateComponents([.year, .month], from: dateCursor)
                    dueDateComponents.day = mutableCard.dueDate
                    
                    if let paymentDate = calendar.date(from: dueDateComponents) {
                        if paymentDate <= today {
                            if paymentDate >= creationDate {
                                paymentsMade += 1
                            }
                        }
                    }
                    
                    guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: dateCursor) else { break }
                    dateCursor = nextMonth
                }
                
                let newRemaining = max(0, totalInstallments - paymentsMade)
                if mutableCard.remainingInstallments != newRemaining {
                    mutableCard.remainingInstallments = newRemaining
                    needsSave = true
                }
            }
            
            return mutableCard
        }
        
        if needsSave {
            self.cards = updatedCards
            saveCards()
        }
    }
    
    func card(withId id: UUID) -> CreditCard? {
        return cards.first(where: { $0.id == id })
    }

    func forceReload() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
