import Foundation
import SwiftUI

// Ödeme türleri enum'ı
enum PaymentType: String, CaseIterable, Identifiable, Codable {
    case card
    case loan
    case oneTimePayment
    case subscription

    var id: String { self.rawValue }

    var defaultPaymentDueDaysOffset: Int {
        switch self {
        case .card: return 10
        case .loan, .oneTimePayment, .subscription: return 0
        }
    }

    var localizationKey: String {
        switch self {
        case .card: return "PAYMENT_TYPE_CARD"
        case .loan: return "PAYMENT_TYPE_LOAN"
        case .oneTimePayment: return "PAYMENT_TYPE_ONETIME"
        case .subscription: return "PAYMENT_TYPE_SUBSCRIPTION"
        }
    }

    var systemIconName: String {
        switch self {
        case .card:
            return "widget.small"
        case .loan:
            return "checkmark.seal.text.page"
        case .oneTimePayment:
            return "dollarsign.circle"
        case .subscription:
            return "person.2.arrow.trianglehead.counterclockwise"
        }
    }
    
    var groupHeader: LocalizedStringKey {
        switch self {
        case .card: return "PAYMENT_TYPE_CARD_HEADER"
        case .loan: return "PAYMENT_TYPE_LOAN_HEADER"
        case .oneTimePayment: return "PAYMENT_TYPE_ONETIME_HEADER"
        case .subscription: return "PAYMENT_TYPE_SUBSCRIPTION_HEADER"
        }
    }
}

// Abonelik ödeme döngüsü enum'ı
enum BillingCycle: String, CaseIterable, Identifiable, Codable {
    case monthly
    case annually

    var id: String { self.rawValue }

    var localizationKey: String {
        switch self {
        case .monthly: return "BILLING_CYCLE_MONTHLY"
        case .annually: return "BILLING_CYCLE_ANNUALLY"
        }
    }
}

// MARK: - CreditCard Modeli

struct CreditCard: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var lastFourDigits: String
    var dueDate: Int
    var paymentDueDaysOffset: Int
    var isActive: Bool
    var color: String
    var type: PaymentType

    // Krediye özgü alanlar
    var totalInstallments: Int?
    var remainingInstallments: Int?
    var creationDate: Date?

    // Aboneliğe özgü alanlar
    var billingCycle: BillingCycle?
    var annualBillingMonth: Int?
    
    // Çevrimdışı silme için yeni alan
    var isDeleted: Bool = false

    // Ana başlatıcı (GÜNCELLENDİ)
    init(
        id: UUID = UUID(),
        name: String,
        lastFourDigits: String = "",
        dueDate: Int,
        paymentDueDaysOffset: Int,
        isActive: Bool = true,
        color: String = "blue",
        type: PaymentType = .card,
        totalInstallments: Int? = nil,
        remainingInstallments: Int? = nil,
        creationDate: Date? = nil,
        billingCycle: BillingCycle? = nil,
        annualBillingMonth: Int? = nil,
        isDeleted: Bool = false // YENİ
    ) {
        self.id = id
        self.name = name
        self.lastFourDigits = lastFourDigits
        self.dueDate = dueDate
        self.paymentDueDaysOffset = paymentDueDaysOffset
        self.isActive = isActive
        self.color = color
        self.type = type
        self.totalInstallments = totalInstallments
        self.remainingInstallments = remainingInstallments
        self.creationDate = creationDate
        self.billingCycle = billingCycle
        self.annualBillingMonth = annualBillingMonth
        self.isDeleted = isDeleted // YENİ
    }

    // Codable anahtarları (GÜNCELLENDİ)
    enum CodingKeys: String, CodingKey {
        case id, name, lastFourDigits, dueDate, paymentDueDaysOffset, isActive, color, type
        case totalInstallments, remainingInstallments, creationDate
        case loanInstallments
        case billingCycle, annualBillingMonth
        case isDeleted // YENİ
    }

    // Kod çözücü (Decodable) (GÜNCELLENDİ)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastFourDigits = try container.decodeIfPresent(String.self, forKey: .lastFourDigits) ?? ""
        self.dueDate = try container.decode(Int.self, forKey: .dueDate)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.color = try container.decode(String.self, forKey: .color)
        self.type = try container.decodeIfPresent(PaymentType.self, forKey: .type) ?? .card
        self.paymentDueDaysOffset = try container.decodeIfPresent(Int.self, forKey: .paymentDueDaysOffset) ?? self.type.defaultPaymentDueDaysOffset
        let total = try container.decodeIfPresent(Int.self, forKey: .totalInstallments)
        let legacyTotal = try container.decodeIfPresent(Int.self, forKey: .loanInstallments)
        self.totalInstallments = total ?? legacyTotal
        self.remainingInstallments = try container.decodeIfPresent(Int.self, forKey: .remainingInstallments) ?? self.totalInstallments
        self.creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        self.billingCycle = try container.decodeIfPresent(BillingCycle.self, forKey: .billingCycle)
        self.annualBillingMonth = try container.decodeIfPresent(Int.self, forKey: .annualBillingMonth)
        // isDeleted alanı yoksa false varsay (eski verilerle uyumluluk için)
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false // YENİ
    }

    // Encodable implementasyonu (GÜNCELLENDİ)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lastFourDigits, forKey: .lastFourDigits)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(paymentDueDaysOffset, forKey: .paymentDueDaysOffset)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(color, forKey: .color)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(totalInstallments, forKey: .totalInstallments)
        try container.encodeIfPresent(remainingInstallments, forKey: .remainingInstallments)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(billingCycle, forKey: .billingCycle)
        try container.encodeIfPresent(annualBillingMonth, forKey: .annualBillingMonth)
        try container.encode(isDeleted, forKey: .isDeleted) // YENİ
    }
    
    // Hashable uyumu
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable uyumu (GÜNCELLENDİ)
    static func == (lhs: CreditCard, rhs: CreditCard) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastFourDigits == rhs.lastFourDigits &&
        lhs.dueDate == rhs.dueDate &&
        lhs.paymentDueDaysOffset == rhs.paymentDueDaysOffset &&
        lhs.isActive == rhs.isActive &&
        lhs.color == rhs.color &&
        lhs.type == rhs.type &&
        lhs.totalInstallments == rhs.totalInstallments &&
        lhs.remainingInstallments == rhs.remainingInstallments &&
        lhs.creationDate == rhs.creationDate &&
        lhs.billingCycle == rhs.billingCycle &&
        lhs.annualBillingMonth == rhs.annualBillingMonth &&
        lhs.isDeleted == rhs.isDeleted // YENİ
    }
}

// MARK: - CreditCardEntity Modeli

struct CreditCardEntity: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var lastFourDigits: String
    var dueDate: Int
    var paymentDueDaysOffset: Int
    var isActive: Bool
    var color: String
    var type: PaymentType

    // Krediye özgü alanlar
    var totalInstallments: Int?
    var remainingInstallments: Int?
    var creationDate: Date?

    // Aboneliğe özgü alanlar
    var billingCycle: BillingCycle?
    var annualBillingMonth: Int?

    // Çevrimdışı silme için yeni alan
    var isDeleted: Bool = false

    // Ana başlatıcı (GÜNCELLENDİ)
    init(
        id: UUID = UUID(),
        name: String,
        lastFourDigits: String = "",
        dueDate: Int,
        paymentDueDaysOffset: Int,
        isActive: Bool = true,
        color: String = "blue",
        type: PaymentType = .card,
        totalInstallments: Int? = nil,
        remainingInstallments: Int? = nil,
        creationDate: Date? = nil,
        billingCycle: BillingCycle? = nil,
        annualBillingMonth: Int? = nil,
        isDeleted: Bool = false // YENİ
    ) {
        self.id = id
        self.name = name
        self.lastFourDigits = lastFourDigits
        self.dueDate = dueDate
        self.paymentDueDaysOffset = paymentDueDaysOffset
        self.isActive = isActive
        self.color = color
        self.type = type
        self.totalInstallments = totalInstallments
        self.remainingInstallments = remainingInstallments
        self.creationDate = creationDate
        self.billingCycle = billingCycle
        self.annualBillingMonth = annualBillingMonth
        self.isDeleted = isDeleted // YENİ
    }

    // Codable anahtarları (GÜNCELLENDİ)
    enum CodingKeys: String, CodingKey {
        case id, name, lastFourDigits, dueDate, paymentDueDaysOffset, isActive, color, type
        case totalInstallments, remainingInstallments, creationDate
        case loanInstallments
        case billingCycle, annualBillingMonth
        case isDeleted // YENİ
    }

    // Kod çözücü (Decodable) (GÜNCELLENDİ)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.lastFourDigits = try container.decodeIfPresent(String.self, forKey: .lastFourDigits) ?? ""
        self.dueDate = try container.decode(Int.self, forKey: .dueDate)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.color = try container.decode(String.self, forKey: .color)
        self.type = try container.decodeIfPresent(PaymentType.self, forKey: .type) ?? .card
        self.paymentDueDaysOffset = try container.decodeIfPresent(Int.self, forKey: .paymentDueDaysOffset) ?? self.type.defaultPaymentDueDaysOffset
        let total = try container.decodeIfPresent(Int.self, forKey: .totalInstallments)
        let legacyTotal = try container.decodeIfPresent(Int.self, forKey: .loanInstallments)
        self.totalInstallments = total ?? legacyTotal
        self.remainingInstallments = try container.decodeIfPresent(Int.self, forKey: .remainingInstallments) ?? self.totalInstallments
        self.creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        self.billingCycle = try container.decodeIfPresent(BillingCycle.self, forKey: .billingCycle)
        self.annualBillingMonth = try container.decodeIfPresent(Int.self, forKey: .annualBillingMonth)
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false // YENİ
    }

    // Encodable implementasyonu (GÜNCELLENDİ)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(lastFourDigits, forKey: .lastFourDigits)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(paymentDueDaysOffset, forKey: .paymentDueDaysOffset)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(color, forKey: .color)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(totalInstallments, forKey: .totalInstallments)
        try container.encodeIfPresent(remainingInstallments, forKey: .remainingInstallments)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(billingCycle, forKey: .billingCycle)
        try container.encodeIfPresent(annualBillingMonth, forKey: .annualBillingMonth)
        try container.encode(isDeleted, forKey: .isDeleted) // YENİ
    }
    
    // Hashable uyumu
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Equatable uyumu (GÜNCELLENDİ)
    static func == (lhs: CreditCardEntity, rhs: CreditCardEntity) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.lastFourDigits == rhs.lastFourDigits &&
        lhs.dueDate == rhs.dueDate &&
        lhs.paymentDueDaysOffset == rhs.paymentDueDaysOffset &&
        lhs.isActive == rhs.isActive &&
        lhs.color == rhs.color &&
        lhs.type == rhs.type &&
        lhs.totalInstallments == rhs.totalInstallments &&
        lhs.remainingInstallments == rhs.remainingInstallments &&
        lhs.creationDate == rhs.creationDate &&
        lhs.billingCycle == rhs.billingCycle &&
        lhs.annualBillingMonth == rhs.annualBillingMonth &&
        lhs.isDeleted == rhs.isDeleted // YENİ
    }
}
