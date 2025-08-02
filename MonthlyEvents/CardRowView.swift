import SwiftUI
import os.log

struct CardRowView: View {
    let card: CreditCard
    
    // --- BURASI GÜNCELLENDİ ---
    // 'let' yerine '@ObservedObject' kullanılarak, bu görünümün
    // HolidayService'deki değişiklikleri dinlemesi ve kendini otomatik
    // olarak güncellemesi sağlanır.
    @ObservedObject var holidayService: HolidayService
    
    @Environment(\.locale) var currentLocale

    // MARK: - Properties
    private var cardColor: Color { colorFromString(card.color) }
    private var textColorOnCard: Color { contrastingTextColor(for: cardColor) }
    
    private var displayFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = currentLocale
        return df
    }

    // MARK: - Body
    var body: some View {
        HStack(spacing: 15) {
            cardIconView
                .frame(width: 45, height: 33)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                    .fontWeight(.bold)

                if card.type == .card, !card.lastFourDigits.isEmpty {
                    Text("**** \(card.lastFourDigits)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if card.type == .loan,
                   let remaining = card.remainingInstallments,
                   let total = card.totalInstallments {
                    
                    if remaining > 0 {
                        Text(String(format: NSLocalizedString("LOAN_INSTALLMENT_STATUS", comment: ""), remaining, total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    } else {
                        Text(LocalizedStringKey("LOAN_COMPLETED"))
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                }
                
                if card.type == .subscription {
                    if card.billingCycle == .annually, let annualMonth = card.annualBillingMonth {
                        Text(String(format: localizedString("SUBSCRIPTION_ANNUAL_STATUS", locale: currentLocale), localizedMonthName(month: annualMonth, locale: currentLocale)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(LocalizedStringKey("SUBSCRIPTION_MONTHLY_STATUS"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                paymentStatusView
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Subviews
    
    @ViewBuilder
    private var cardIconView: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardColor)
                .frame(width: 45, height: 33)

            Image(systemName: card.type.systemIconName)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(textColorOnCard)
                .padding(.leading, 5)
                .offset(x: 0, y: -5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if card.type == .card || card.type == .loan || card.type == .oneTimePayment || card.type == .subscription {
                Text("\(card.dueDate)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(textColorOnCard)
                    .padding([.bottom, .trailing], 4)
            }
        }
    }
    
    @ViewBuilder
    private var paymentStatusView: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dueDates = DueDateCalculator.calculateDueDates(for: card, referenceDate: today, using: holidayService)
        let isDueToday = dueDates.contains { calendar.isDate($0, inSameDayAs: today) }

        if isDueToday {
            dueTodayView(dueDates: dueDates, calendar: calendar, today: today)
        } else if let firstDueDate = dueDates.first {
            nextDueDateView(firstDueDate: firstDueDate, calendar: calendar)
        } else {
            if card.type == .loan, (card.remainingInstallments ?? 1) <= 0 {
                Text(LocalizedStringKey("LOAN_COMPLETED"))
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.semibold)
            } else if card.type != .loan {
                 Text(LocalizedStringKey("DUE_DATE_UNAVAILABLE"))
                     .font(.caption)
                     .foregroundColor(.gray)
            }
        }
    }
    
    private func dueTodayView(dueDates: [Date], calendar: Calendar, today: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey("PAYMENT_DAY_TODAY"))
                .font(.caption)
                .foregroundColor(.red)
                .fontWeight(.semibold)

            if let nextDueDate = dueDates.first(where: { !calendar.isDate($0, inSameDayAs: today) }) {
                let nextMonthText = String(format: localizedString("NEXT_MONTH_DUE_DATE", locale: currentLocale), displayFormatter.string(from: nextDueDate))
                Text(nextMonthText)
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
    }
    
    private func nextDueDateView(firstDueDate: Date, calendar: Calendar) -> some View {
        let dueDateText = String(
            format: localizedString("DUE_DATE_DISPLAY", locale: currentLocale),
            displayFormatter.string(from: firstDueDate)
        )
        
        return HStack(alignment: .center, spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundColor(.orange)

            Text(dueDateText)
                .font(.caption)
                .foregroundColor(.orange)
                .fontWeight(.medium)
        }
    }

    // MARK: - Helper Functions
    
    private func colorFromString(_ nameOrHex: String) -> Color {
        if nameOrHex.hasPrefix("#") {
            let hex = nameOrHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let a, r, g, b: UInt64
            switch hex.count {
            case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default: (a, r, g, b) = (255, 128, 128, 128)
            }
            return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
        } else {
            switch nameOrHex.lowercased() {
            case "blue": return .blue
            case "red": return .red
            case "green": return .green
            case "orange": return .orange
            case "purple": return .purple
            default: return .gray
            }
        }
    }

    private func contrastingTextColor(for backgroundColor: Color) -> Color {
        let uiColor = UIColor(backgroundColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        if a < 0.5 { return .primary }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5 ? .black : .white
    }
    
    private func localizedString(_ key: String, locale: Locale) -> String {
        if let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        }
        
        if let langCode = locale.languageCode,
           let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        }

        return NSLocalizedString(key, comment: "")
    }

    private func localizedMonthName(month: Int, locale: Locale) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = month
        if let date = calendar.date(from: components) {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateFormat = "MMMM" // Ayın tam adı
            return dateFormatter.string(from: date)
        }
        return ""
    }
}
