import SwiftUI
import Foundation

class CardDataManager: ObservableObject {
    static let shared = CardDataManager()
    @Published var cards: [CreditCard] = []
    private let cardsKey = "SavedCreditCards"

    private init() {
        loadCards()
    }

    private func loadCards() {
        if let data = UserDefaults.standard.data(forKey: cardsKey) {
            let decoder = JSONDecoder()
            if let decodedCards = try? decoder.decode([CreditCard].self, from: data) {
                cards = decodedCards
            }
        }
    }

    private func saveCards() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(cards) {
            UserDefaults.standard.set(encoded, forKey: cardsKey)
        }
    }

    // MARK: - Public API

    func addCard(_ card: CreditCard) {
        cards.append(card)
        saveCards()
        rescheduleAllEventsAndNotifications()
        forceReload()
    }

    func updateCard(_ card: CreditCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
        saveCards()
        rescheduleAllEventsAndNotifications()
        forceReload()
    }
    
    /// Tek bir öğeyi siler. Örneğin, düzenleme ekranındaki silme butonu için kullanılır.
    func delete(card: CreditCard) {
        performDeletion(for: card)
    }

    /// Gruplanmış bir listeden, `.onDelete` ile gelen IndexSet'e göre öğeleri siler.
    func delete(in group: [CreditCard], at offsets: IndexSet) {
        let cardsToDelete = offsets.map { group[$0] }
        for card in cardsToDelete {
            performDeletion(for: card)
        }
    }
    
    // MARK: - Private Deletion Logic

    private func performDeletion(for card: CreditCard) {
        // 1. Öğeyi ana veri dizisinden kaldır.
        cards.removeAll(where: { $0.id == card.id })
        
        // 2. Değişiklikleri kaydet.
        saveCards()
        
        // 3. Değişiklik sonrası TÜM etkinlik ve bildirimleri yeniden planla.
        rescheduleAllEventsAndNotifications()
        
        // 4. Arayüzü güncelle.
        forceReload()
    }

    // MARK: - Central Rescheduling Logic (GÜNCELLENDİ)

    /// Takvimi ve tüm bildirimleri tamamen sıfırlar ve mevcut kartlara göre yeniden oluşturur.
    func rescheduleAllEventsAndNotifications() {
        Task {
            let hasCalendarAccess = await CalendarManager.shared.requestAccessIfNeeded()
            let hasNotificationAccess = await NotificationManager.shared.requestPermission()
            
            // Çeviriler için doğru 'locale' bilgisini al (takvim adı için gerekli)
            let languageIdentifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.current.identifier
            let locale = Locale(identifier: languageIdentifier)
            
            // 1. ADIM: "Hard Reset" - Takvimi ve tüm planları temizle
            if hasCalendarAccess {
                // Takvimin kendisini silip yeniden oluşturur
                CalendarManager.shared.resetAndCreateNewCalendar(for: locale)
            }
            if hasNotificationAccess {
                // Planlanmış tüm bildirimleri iptal eder
                NotificationManager.shared.removeAllScheduledNotifications()
            }
            
            let holidayService = HolidayService.shared

            // 2. ADIM: Mevcut kart listesine göre her şeyi yeniden oluştur
            for card in cards where card.isActive {
                let dueDates = DueDateCalculator.calculateDueDates(for: card, using: holidayService)
                
                if hasCalendarAccess {
                    // Etkinlikleri yeni oluşturulan takvime ekler
                    CalendarManager.shared.addOrUpdateEvents(for: card, dueDates: dueDates, holidayService: holidayService, locale: locale)
                }
                
                if hasNotificationAccess {
                    // Bildirimleri yeniden planlar
                    NotificationManager.shared.scheduleReminders(for: card, dueDates: dueDates, locale: locale)
                }
            }
            
            print("Takvim ve bildirimler 'hard reset' yöntemiyle yeniden planlandı.")
        }
    }

    // MARK: - Other Functions
    
    // GÜNCELLENDİ: Hem kredi taksitlerini hem de abonelikleri güncellemek için daha genel bir ad
    func updateInstallmentsAndSubscriptions() {
        var needsSave = false
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let updatedCards = cards.map { card -> CreditCard in
            var mutableCard = card
            
            // Kredi taksitlerini güncelleme mantığı
            if mutableCard.type == .loan,
               let creationDate = mutableCard.creationDate,
               let totalInstallments = mutableCard.totalInstallments {
                
                var paymentsMade = 0
                var dateCursor = creationDate
                
                // Kredi başlangıç ayının ilk gününü al
                var initialLoanCheckDateComponents = calendar.dateComponents([.year, .month], from: creationDate)
                initialLoanCheckDateComponents.day = mutableCard.dueDate // Kredi ödeme gününü ayarla
                guard let loanStartPaymentDate = calendar.date(from: initialLoanCheckDateComponents) else { return card }

                // Kredi başlangıç ayının ödeme günü, oluşturulma tarihinden sonraysa ilk taksiti sayma
                if creationDate <= loanStartPaymentDate {
                    // Eğer oluşum tarihi ödeme gününden önce veya ödeme günü ile aynıysa, ilk ödeme dönemi bu ay başlar
                    paymentsMade = 0 // Henüz ödeme yapılmamış varsay
                } else {
                    // Eğer oluşum tarihi ödeme gününden sonra ise, bu ayın taksitini ödenmiş varsayabiliriz (veya bir sonraki aydan başlar)
                    // Bu senaryo için başlangıçta 0 taksit ödenmiş kabul ediyoruz, döngü ilerideki ayları kontrol edecek.
                    paymentsMade = 0
                }

                // Oluşturulma tarihinden bugüne kadar olan ayları döngüye al
                while dateCursor < today {
                    var dueDateComponents = calendar.dateComponents([.year, .month], from: dateCursor)
                    dueDateComponents.day = mutableCard.dueDate // Ödeme gününü ayın ilgili gününe ayarla
                    
                    if let paymentDate = calendar.date(from: dueDateComponents) {
                        // Eğer ödeme tarihi bugünden önce veya bugün ise VE o ayın ödeme günü oluşturulma tarihinden büyükse say.
                        // Bu, özellikle oluşturulma tarihinden sonraki ilk ödeme gününü doğru saymak için önemli.
                        if paymentDate <= today {
                             // İlk taksit için özel kontrol: Oluşturulma tarihinden sonraki ilk ödeme gününü dikkate al.
                             // dateCursor'ın bulunduğu ayın ödeme günü oluşum tarihinden sonra ise saymaya başla.
                            if paymentDate >= creationDate {
                                paymentsMade += 1
                            }
                        }
                    }
                    
                    guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: dateCursor) else { break }
                    dateCursor = nextMonth
                }
                
                // paymentsMade, taksit sayısını aştıysa sıfırla
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
