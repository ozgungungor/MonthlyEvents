import SwiftUI // ObservableObject, @Published için
import Foundation // UserDefaults için

// Sorumluluk: Kart verilerini UserDefaults kullanarak saklar ve yönetir.
class CardDataManager: ObservableObject {
    static let shared = CardDataManager() // AppDelegate erişimi için singleton
    
    @Published var cards: [CreditCard] = []
    private let cardsKey = "SavedCreditCards"
    
    private init() {
        loadCards()
    }
    
    private func loadCards() {
        if let data = UserDefaults.standard.data(forKey: cardsKey),
           let decodedCards = try? JSONDecoder().decode([CreditCard].self, from: data) {
            cards = decodedCards
        }
    }
    
    private func saveCards() {
        if let encoded = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(encoded, forKey: cardsKey)
        }
    }
    
    func addCard(_ card: CreditCard) {
        cards.append(card)
        saveCards()
    }
    
    func updateCard(_ card: CreditCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
            saveCards()
        }
    }
    
    func deleteCard(at offsets: IndexSet) {
        for index in offsets {
            let card = cards[index]
            CalendarManager.shared.removeEvent(for: card) // Takvimden sil
            NotificationManager.shared.removeReminders(for: card)
        }
        cards.remove(atOffsets: offsets)
        saveCards()
    }


    // AppDelegate için UUID ile kartı bulma
    func card(withId id: UUID) -> CreditCard? {
        return cards.first(where: { $0.id == id })
    }
}
