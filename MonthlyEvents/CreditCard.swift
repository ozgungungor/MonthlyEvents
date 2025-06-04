import Foundation // UUID ve Codable için

struct CreditCard: Identifiable, Codable {
    let id: UUID
    var name: String
    var lastFourDigits: String
    var dueDate: Int // Ayın hangi günü (1-31)
    var isActive: Bool
    var color: String
    
    init(id: UUID = UUID(), name: String = "", lastFourDigits: String = "", dueDate: Int = 1, isActive: Bool = true, color: String = "blue") {
        self.id = id
        self.name = name
        self.lastFourDigits = lastFourDigits
        self.dueDate = dueDate
        self.isActive = isActive
        self.color = color
    }
}
