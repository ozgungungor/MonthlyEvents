import Foundation

struct CreditCard: Identifiable, Codable {
    let id: UUID
    var name: String
    var lastFourDigits: String
    var dueDate: Int
    var paymentDueDaysOffset: Int
    var isActive: Bool
    var color: String
    
    // Varsayılan init'i olduğu gibi bırakabiliriz, bu form gibi yerlerde kullanışlıdır.
    init(id: UUID = UUID(), name: String = "", lastFourDigits: String = "", dueDate: Int = 1, paymentDueDaysOffset: Int = 10, isActive: Bool = true, color: String = "blue") {
        self.id = id
        self.name = name
        self.lastFourDigits = lastFourDigits
        self.dueDate = dueDate
        self.paymentDueDaysOffset = paymentDueDaysOffset
        self.isActive = isActive
        self.color = color
    }
    
    // YENİ: Veri modelindeki alanları tanımlayan CodingKeys
    enum CodingKeys: String, CodingKey {
        case id, name, lastFourDigits, dueDate, paymentDueDaysOffset, isActive, color
    }
    
    // YENİ: Özel kod çözme (decoding) init'i
    // Bu metod, JSON'dan veri okunurken çalışır.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Mevcut alanları normal şekilde oku
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastFourDigits = try container.decode(String.self, forKey: .lastFourDigits)
        self.dueDate = try container.decode(Int.self, forKey: .dueDate)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.color = try container.decode(String.self, forKey: .color)
        
        // Yeni 'paymentDueDaysOffset' alanını okumayı dene.
        // `decodeIfPresent`: Eğer anahtar JSON'da varsa oku, yoksa nil döndür.
        // `?? 10`: Eğer sonuç nil ise (yani eski veride bu alan yoksa), varsayılan olarak 10 ata.
        self.paymentDueDaysOffset = try container.decodeIfPresent(Int.self, forKey: .paymentDueDaysOffset) ?? 10
    }
}
