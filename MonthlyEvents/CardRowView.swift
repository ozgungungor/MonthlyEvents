import SwiftUI
import os.log

struct CardRowView: View {
    let card: CreditCard
    let holidayService: HolidayService
    @Environment(\.locale) var currentLocale // Ortamdan mevcut locale'i al

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CardRowView")
    
    // displayFormatter'ı bir computed property yapıyoruz ki locale değişimini alabilsin
    private var displayFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .long
        df.locale = currentLocale // Ortamdan alınan locale'i kullan
        return df
    }

    // debugFormatter'ı da benzer şekilde güncelliyoruz
    // Genellikle debug formatlayıcılarının locale'den bağımsız olması tercih edilebilir
    // ama tutarlılık için bunu da güncelleyebiliriz veya sabit bir locale (örn: "en_US_POSIX") kullanabiliriz.
    private var debugFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd (EEEE)" // Formatı İngilizce karakterlerle tutmak genellikle daha güvenlidir
        df.locale = currentLocale // Ortamdan alınan locale'i kullan
        return df
    }

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

    private var cardColor: Color {
        colorFromString(card.color)
    }

    private var cardConfiguredDueDateDay: Int {
        return card.dueDate
    }

    private func contrastingTextColor(for backgroundColor: Color) -> Color {
        let uiColor = UIColor(backgroundColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        if a < 0.5 { return Color(UIColor.darkText) }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.5 ? Color(UIColor.darkText) : Color(UIColor.lightText)
    }

    private func localizedString(_ key: String, locale: Locale) -> String {
        if let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        }
        return key
    }
    
    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // logger.info("[CardRowView] '\(card.name)' için render ediliyor. Kart Rengi: \(card.color), Yapılandırılmış Son Ödeme Günü: \(cardConfiguredDueDateDay). Bugün: \(self.debugFormatter.string(from: today))")

        let dueDates = DueDateCalculator.calculateDueDates(for: card, referenceDate: today, using: holidayService)
        let isDueToday = dueDates.contains(where: { calendar.isDate($0, inSameDayAs: today) })

        let paymentStatusView: AnyView = {
            if isDueToday {
                var views: [AnyView] = [
                    AnyView(Text(LocalizedStringKey("PAYMENT_DAY_TODAY"))) // Yerelleştirilmiş metin
                ]
                if dueDates.count > 1 && !calendar.isDate(dueDates[1], inSameDayAs: today) {
                    let nextActualDueDate = dueDates[1]
                    let nextMonthText = String(format: NSLocalizedString("NEXT_MONTH_DUE_DATE", comment: "Sonraki ayın son ödeme tarihi"), displayFormatter.string(from: nextActualDueDate))
                    views.append(AnyView(Text(nextMonthText)))
                }
                // Styling for these texts should be applied directly here
                return AnyView(VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<views.count, id: \.self) { index in
                        if index == 0 { // First item: "Ödeme Günü: Bugün"
                            views[index]
                                .font(.caption)
                                .foregroundColor(.red)
                                .fontWeight(.semibold)
                        } else { // Second item: "Sonraki Ay..."
                            views[index]
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                })
            } else if let firstCalculatedDueDate = dueDates.first {
                let actualPaymentDayOfMonth = calendar.component(.day, from: firstCalculatedDueDate)
                let iconForegroundColor = Color.orange
                let textColorForSmallCalendarIcon = contrastingTextColor(for: iconForegroundColor)
                
                let dueDateText = String(
                    format: localizedString("DUE_DATE_DISPLAY", locale: currentLocale),
                    displayFormatter.string(from: firstCalculatedDueDate)
                )


                return AnyView(
                    HStack(alignment: .center, spacing: 4) {
                        ZStack {
                            Image(systemName: "calendar")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(iconForegroundColor)
                            Text("\(actualPaymentDayOfMonth)")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(textColorForSmallCalendarIcon)
                                .offset(y: 0.5)
                        }
                        .frame(width: 15, height: 15)

                        Text(dueDateText)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                )
            } else {
                return AnyView(Text(LocalizedStringKey("DUE_DATE_UNAVAILABLE"))
                    .font(.caption)
                    .foregroundColor(.gray))
            }
        }()

        let numberColorOnCard = contrastingTextColor(for: cardColor)

        return HStack {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "creditcard.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(cardColor)

                Text("\(cardConfiguredDueDateDay)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(numberColorOnCard)
                    .padding(.trailing, 5)
                    .padding(.bottom, 3)
            }
            .frame(width: 45, height: 33)
            .padding(.trailing, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)
                    .fontWeight(.bold)

                Text("**** \(card.lastFourDigits)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                paymentStatusView
            }
        }
        .padding(.vertical, 8)
    }
}
