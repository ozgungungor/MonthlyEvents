import Foundation
import os.log

// CreditCard struct'ının projenizde başka bir yerde tanımlı olduğunu varsayıyorum.
// Örnek:
// struct CreditCard {
//     let name: String
//     let dueDate: Int // Ayın günü (1-31) olarak hesap kesim tarihi
// }

// SimpleHolidayService struct'ı artık gerekli değil, silindi.

// MARK: - Due Date Calculator

enum DueDateCalculator {
    // debugFormatter'ı fileprivate yaptık, böylece aynı dosyadaki test fonksiyonu erişebilir.
    fileprivate static let debugFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z (EEEE)"
        df.locale = Locale(identifier: "tr_TR")
        df.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return df
    }()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.DueDateCalculatorApp", category: "DueDateCalculator")

    // holidayService parametresinin tipi HolidayService (senin class'ın) olarak değiştirildi.
    static func calculateDueDates(for card: CreditCard, using holidayService: HolidayService) -> [Date] {
        let actualToday = Date()
        logger.info("""
            [CALC_DUE_DATES_WRAPPER] Hesaplama gerçek 'bugün' ile tetikleniyor.
            Gerçek Bugün (Sistem Saati): \(self.debugFormatter.string(from: actualToday))
            Ana fonksiyona bu tarih gönderilecek ve ana fonksiyon iç mantığına göre -10 gün uygulayacak.
            """)
        // holidayService parametresi doğrudan senin class'ının bir örneği olacak.
        return calculateDueDates(for: card, referenceDate: actualToday, using: holidayService)
    }

    // holidayService parametresinin tipi HolidayService (senin class'ın) olarak değiştirildi.
    static func calculateDueDates(for card: CreditCard, referenceDate originalReferenceDateInput: Date, using holidayService: HolidayService) -> [Date] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!

        guard let tenDaysSubtractedDate = calendar.date(byAdding: .day, value: -10, to: originalReferenceDateInput) else {
            logger.critical("""
                [CALC_DUE_DATES_CORE] KRİTİK HATA:
                Gelen referans tarihinden (\(self.debugFormatter.string(from: originalReferenceDateInput))) 10 gün çıkarılamadı!
                Bu durum beklenmiyor. Boş dizi döndürülüyor.
                """)
            return []
        }

        let calculationReferenceDayStart = calendar.startOfDay(for: tenDaysSubtractedDate)
        let comparisonReferenceDayStart = calendar.startOfDay(for: originalReferenceDateInput)

        logger.info("""
            [CALC_DUE_DATES_CORE] Hesaplama Başladı:
            Fonksiyona Gelen Orijinal Referans Tarih (Karşılaştırma için): \(self.debugFormatter.string(from: comparisonReferenceDayStart))
            10 Gün Çıkarıldıktan Sonraki Hesaplama Kök Tarihi (Ay belirleme için): \(self.debugFormatter.string(from: calculationReferenceDayStart))
            Kart Adı: \(card.name)
            Kart Hesap Kesim Günü (Ayın): \(card.dueDate)
            """)

        var componentsForStatementMonth = calendar.dateComponents([.year, .month], from: calculationReferenceDayStart)

        if let dateForStatementMonth = calendar.date(from: componentsForStatementMonth),
           let monthRange = calendar.range(of: .day, in: .month, for: dateForStatementMonth) {
            let originalStatementDay = card.dueDate
            componentsForStatementMonth.day = min(originalStatementDay, monthRange.count)
            if originalStatementDay > monthRange.count {
                logger.warning("""
                    [CALC_DUE_DATES_CORE] Kart hesap kesim günü (\(originalStatementDay))
                    hesaplama referans ayının (\(componentsForStatementMonth.month ?? 0)/\(componentsForStatementMonth.year ?? 0))
                    gün sayısını (\(monthRange.count)) aşıyor.
                    Ayın son günü (\(componentsForStatementMonth.day ?? 0)) kullanıldı.
                    """)
            }
        } else {
            componentsForStatementMonth.day = card.dueDate
            logger.error("[CALC_DUE_DATES_CORE] Hesaplama referans ayının gün aralığı alınamadı. Direkt card.dueDate (\(card.dueDate)) kullanılıyor.")
        }

        guard let thisMonthStatementDate = calendar.date(from: componentsForStatementMonth) else {
            logger.error("""
                [CALC_DUE_DATES_CORE] HATA: Hesaplama referans ayı için hesap kesim tarihi oluşturulamadı.
                Bileşenler: Y: \(componentsForStatementMonth.year ?? -1) M: \(componentsForStatementMonth.month ?? -1) D: \(componentsForStatementMonth.day ?? -1)
                """)
            return []
        }
        logger.debug("[CALC_DUE_DATES_CORE] Hesaplama Referans Ayı İçin Hesap Kesim Tarihi: \(self.debugFormatter.string(from: thisMonthStatementDate))")

        guard let tenDaysAddedToStatement = calendar.date(byAdding: .day, value: 10, to: thisMonthStatementDate) else {
            logger.error("[CALC_DUE_DATES_CORE] HATA: \(self.debugFormatter.string(from: thisMonthStatementDate)) tarihine 10 gün eklenemedi.")
            return []
        }
        logger.debug("[CALC_DUE_DATES_CORE] 10 Gün Eklenmiş Ham Son Ödeme Tarihi: \(self.debugFormatter.string(from: tenDaysAddedToStatement))")

        // holidayService.findNextWorkingDay(from:) çağrısı doğrudan senin class'ındaki metodu çağıracak.
        let thisMonthCalculatedDueDate = holidayService.findNextWorkingDay(from: tenDaysAddedToStatement)
        logger.debug("[CALC_DUE_DATES_CORE] Hesaplama Referans Ayı İçin Son Ödeme Tarihi (iş günü): \(self.debugFormatter.string(from: thisMonthCalculatedDueDate))")

        let isPastPaymentComparedToOriginalInput = thisMonthCalculatedDueDate < comparisonReferenceDayStart
        let isTodayComparedToOriginalInput = calendar.isDate(thisMonthCalculatedDueDate, inSameDayAs: comparisonReferenceDayStart)

        logger.debug("""
            [CALC_DUE_DATES_CORE] Karşılaştırma (Orijinal Gelen Tarihe Göre):
            Hesaplanan Son Ödeme (Ref. Ay): \(self.debugFormatter.string(from: thisMonthCalculatedDueDate))
            Orijinal Gelen Referans Tarih (Karşılaştırma Noktası): \(self.debugFormatter.string(from: comparisonReferenceDayStart))
            Ödeme, Orijinal Gelen Ref. Tarihe Göre Geçmişte mi? \(isPastPaymentComparedToOriginalInput)
            Ödeme, Orijinal Gelen Ref. Tarih ile Aynı Gün mü? \(isTodayComparedToOriginalInput)
            """)

        if isTodayComparedToOriginalInput {
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH ile aynı gün.")
            if let nextMonthDueDate = calculateFollowingMonthDueDate(
                currentYear: componentsForStatementMonth.year!,
                currentMonth: componentsForStatementMonth.month!,
                cardStatementDay: card.dueDate,
                calendar: calendar,
                holidayService: holidayService // holidayService parametresinin tipi HolidayService (senin class'ın)
            ) {
                logger.info("""
                    [CALC_DUE_DATES_CORE] Sonuç: [Orijinal Ref. Tarihe Denk Gelen Ödeme, Sonraki Ay Ödemesi]
                    -> [\(self.debugFormatter.string(from: thisMonthCalculatedDueDate)), \(self.debugFormatter.string(from: nextMonthDueDate))]
                    """)
                return [thisMonthCalculatedDueDate, nextMonthDueDate].sorted()
            } else {
                logger.warning("[CALC_DUE_DATES_CORE] Sonraki ay ödeme tarihi hesaplanamadı. Sadece Orijinal Ref. Tarihe denk gelen ödeme döndürülüyor.")
                return [thisMonthCalculatedDueDate]
            }
        } else if isPastPaymentComparedToOriginalInput {
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH'e göre GEÇMİŞTE.")
            if let nextMonthDueDate = calculateFollowingMonthDueDate(
                currentYear: componentsForStatementMonth.year!,
                currentMonth: componentsForStatementMonth.month!,
                cardStatementDay: card.dueDate,
                calendar: calendar,
                holidayService: holidayService // holidayService parametresinin tipi HolidayService (senin class'ın)
            ) {
                logger.info("[CALC_DUE_DATES_CORE] Sonuç: [Sonraki Ay Ödemesi] -> [\(self.debugFormatter.string(from: nextMonthDueDate))]")
                return [nextMonthDueDate]
            } else {
                logger.error("[CALC_DUE_DATES_CORE] Ödeme geçmiş olmasına rağmen sonraki ay ödeme tarihi hesaplanamadı. Boş dizi döndürülüyor.")
                return []
            }
        } else {
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH'e göre GELECEKTE.")
            logger.info("[CALC_DUE_DATES_CORE] Sonuç: [Mevcut Hesap Kesim Periyoduna Ait Ödeme] -> [\(self.debugFormatter.string(from: thisMonthCalculatedDueDate))]")
            return [thisMonthCalculatedDueDate]
        }
    }

    // holidayService parametresinin tipi HolidayService (senin class'ın) olarak değiştirildi.
    private static func calculateFollowingMonthDueDate(
        currentYear: Int,
        currentMonth: Int,
        cardStatementDay: Int,
        calendar: Calendar,
        holidayService: HolidayService // holidayService parametresinin tipi HolidayService (senin class'ın)
    ) -> Date? {
        logger.debug("""
            [CALC_FOLLOWING_MONTH] Sonraki ay son ödeme tarihi hesaplaması başladı.
            Referans Yıl (Hesap Kesim Ayı İçin): \(currentYear), Referans Ay (Hesap Kesim Ayı İçin): \(currentMonth), Kartın Orijinal Kesim Günü: \(cardStatementDay)
            """)

        var nextMonthStatementComponents = DateComponents()
        nextMonthStatementComponents.year = currentYear
        nextMonthStatementComponents.month = currentMonth + 1

        var tempDateForMonthRangeComponents = DateComponents(year: nextMonthStatementComponents.year, month: nextMonthStatementComponents.month, day: 1)

        guard let dateForFollowingMonthInfo = calendar.date(from: tempDateForMonthRangeComponents) else {
            logger.error("""
            [CALC_FOLLOWING_MONTH] Sonraki ay için gün sayısı alınacak tarih oluşturulamadı.
            Bileşenler: Y:\(tempDateForMonthRangeComponents.year ?? -1) M:\(tempDateForMonthRangeComponents.month ?? -1)
            """)
            return nil
        }

        if let monthRange = calendar.range(of: .day, in: .month, for: dateForFollowingMonthInfo) {
            nextMonthStatementComponents.day = min(cardStatementDay, monthRange.count)
            if cardStatementDay > monthRange.count {
                 logger.warning("""
                    [CALC_FOLLOWING_MONTH] Kart hesap kesim günü (\(cardStatementDay))
                    sonraki ayın (\(calendar.component(.month, from: dateForFollowingMonthInfo))/\(calendar.component(.year, from: dateForFollowingMonthInfo)))
                    gün sayısını (\(monthRange.count)) aşıyor.
                    Ayın son günü (\(nextMonthStatementComponents.day ?? 0)) kullanıldı.
                    """)
            }
        } else {
            nextMonthStatementComponents.day = cardStatementDay
            logger.error("[CALC_FOLLOWING_MONTH] Sonraki ayın gün aralığı alınamadı. Direkt cardStatementDay (\(cardStatementDay)) kullanılıyor.")
        }

        guard let nextMonthStatementDate = calendar.date(from: nextMonthStatementComponents) else {
            logger.error("""
                [CALC_FOLLOWING_MONTH] HATA: Sonraki ay için hesap kesim tarihi oluşturulamadı.
                Bileşenler: Y: \(nextMonthStatementComponents.year ?? -1) M: \(nextMonthStatementComponents.month ?? -1) D: \(nextMonthStatementComponents.day ?? -1)
                """)
            return nil
        }
        logger.debug("[CALC_FOLLOWING_MONTH] Sonraki Ay Hesap Kesim Tarihi: \(self.debugFormatter.string(from: nextMonthStatementDate))")

        guard let tenDaysAddedToNextMonthStatement = calendar.date(byAdding: .day, value: 10, to: nextMonthStatementDate) else {
            logger.error("[CALC_FOLLOWING_MONTH] HATA: \(self.debugFormatter.string(from: nextMonthStatementDate)) tarihine 10 gün eklenemedi.")
            return nil
        }
        logger.debug("[CALC_FOLLOWING_MONTH] 10 Gün Eklenmiş Ham Son Ödeme Tarihi (Sonraki Ay): \(self.debugFormatter.string(from: tenDaysAddedToNextMonthStatement))")

        // holidayService.findNextWorkingDay(from:) çağrısı doğrudan senin class'ındaki metodu çağıracak.
        let nextMonthCalculatedDueDate = holidayService.findNextWorkingDay(from: tenDaysAddedToNextMonthStatement)
        logger.debug("[CALC_FOLLOWING_MONTH] Sonraki Ay Son Ödeme Tarihi (iş günü): \(self.debugFormatter.string(from: nextMonthCalculatedDueDate))")
        return nextMonthCalculatedDueDate
    }
}

// MARK: - Example Usage (Test için)
// Bu fonksiyonu çağırmak için CreditCard ve HolidayService (senin class'ın) türlerinin
// projenizde tanımlı ve erişilebilir olması gerekir.
/*
func testDueDateCalculations() {
    // CreditCard struct'ının projenizde tanımlı olduğundan emin olun.
    // struct CreditCard { let name: String; let dueDate: Int }

    let card1 = CreditCard(name: "Test Kart 15", dueDate: 15)
    
    // HolidayService.shared kullanarak test edebilirsiniz (eğer uygunsa)
    // veya test için yeni bir HolidayService örneği oluşturabilirsiniz.
    let holidayServiceInstance = HolidayService.shared // Veya HolidayService() eğer init public/internal ise

    var testCalendar = Calendar.current
    testCalendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!

    var components = DateComponents(timeZone: TimeZone(identifier: "Europe/Istanbul"), year: 2025, month: 5, day: 28, hour: 10)
    var testDate1 = testCalendar.date(from: components)!
    print("\n--- Test 1: Kart Kesim 15, Bugün 28 Mayıs 2025 ---")
    print("Referans Tarih: \(DueDateCalculator.debugFormatter.string(from: testDate1))")
    let dueDates1 = DueDateCalculator.calculateDueDates(for: card1, referenceDate: testDate1, using: holidayServiceInstance)
    dueDates1.forEach { print("Hesaplanan Son Ödeme: \(DueDateCalculator.debugFormatter.string(from: $0))") }

    // Diğer test senaryoları...
    components = DateComponents(timeZone: TimeZone(identifier: "Europe/Istanbul"), year: 2025, month: 5, day: 26, hour: 10)
    var testDate2 = testCalendar.date(from: components)!
    print("\n--- Test 2: Kart Kesim 15, Bugün 26 Mayıs 2025 ---")
    print("Referans Tarih: \(DueDateCalculator.debugFormatter.string(from: testDate2))")
    let dueDates2 = DueDateCalculator.calculateDueDates(for: card1, referenceDate: testDate2, using: holidayServiceInstance)
    dueDates2.forEach { print("Hesaplanan Son Ödeme: \(DueDateCalculator.debugFormatter.string(from: $0))") }

    // ... (diğer test senaryoları da holidayServiceInstance kullanarak güncellenmeli) ...
}

// Testleri çalıştırmak için:
// testDueDateCalculations()
*/
