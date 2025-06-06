import Foundation
import os.log

// MARK: - Due Date Calculator

enum DueDateCalculator {
    fileprivate static let debugFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z (EEEE)"
        df.locale = Locale(identifier: "tr_TR")
        df.timeZone = TimeZone(identifier: "Europe/Istanbul")
        return df
    }()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.DueDateCalculatorApp", category: "DueDateCalculator")

    static func calculateDueDates(for card: CreditCard, using holidayService: HolidayService) -> [Date] {
        let actualToday = Date()
        // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
        logger.info("""
            [CALC_DUE_DATES_WRAPPER] Hesaplama gerçek 'bugün' ile tetikleniyor.
            Gerçek Bugün (Sistem Saati): \(self.debugFormatter.string(from: actualToday))
            Ana fonksiyona bu tarih gönderilecek ve ana fonksiyon iç mantığına göre -'\(card.paymentDueDaysOffset)' gün uygulayacak.
            """)
        return calculateDueDates(for: card, referenceDate: actualToday, using: holidayService)
    }

    static func calculateDueDates(for card: CreditCard, referenceDate originalReferenceDateInput: Date, using holidayService: HolidayService) -> [Date] {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!

        guard let offsetSubtractedDate = calendar.date(byAdding: .day, value: -card.paymentDueDaysOffset, to: originalReferenceDateInput) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.critical("""
                [CALC_DUE_DATES_CORE] KRİTİK HATA:
                Gelen referans tarihinden (\(self.debugFormatter.string(from: originalReferenceDateInput))) \(card.paymentDueDaysOffset) gün çıkarılamadı!
                Bu durum beklenmiyor. Boş dizi döndürülüyor.
                """)
            return []
        }

        let calculationReferenceDayStart = calendar.startOfDay(for: offsetSubtractedDate)
        let comparisonReferenceDayStart = calendar.startOfDay(for: originalReferenceDateInput)

        // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
        logger.info("""
            [CALC_DUE_DATES_CORE] Hesaplama Başladı:
            Fonksiyona Gelen Orijinal Referans Tarih (Karşılaştırma için): \(self.debugFormatter.string(from: comparisonReferenceDayStart))
            \(card.paymentDueDaysOffset) Gün Çıkarıldıktan Sonraki Hesaplama Kök Tarihi (Ay belirleme için): \(self.debugFormatter.string(from: calculationReferenceDayStart))
            Kart Adı: \(card.name, privacy: .public)
            Kart Hesap Kesim Günü (Ayın): \(card.dueDate)
            Kart Ödeme Gün Sayısı Ofseti: \(card.paymentDueDaysOffset)
            """)

        var componentsForStatementMonth = calendar.dateComponents([.year, .month], from: calculationReferenceDayStart)

        if let dateForStatementMonth = calendar.date(from: componentsForStatementMonth),
           let monthRange = calendar.range(of: .day, in: .month, for: dateForStatementMonth) {
            let originalStatementDay = card.dueDate
            componentsForStatementMonth.day = min(originalStatementDay, monthRange.count)
            if originalStatementDay > monthRange.count {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                logger.warning("""
                    [CALC_DUE_DATES_CORE] Kart hesap kesim günü (\(originalStatementDay))
                    hesaplama referans ayının (\(componentsForStatementMonth.month ?? 0)/\(componentsForStatementMonth.year ?? 0))
                    gün sayısını (\(monthRange.count)) aşıyor.
                    Ayın son günü (\(componentsForStatementMonth.day ?? 0)) kullanıldı.
                    """)
            }
        } else {
            componentsForStatementMonth.day = card.dueDate
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("[CALC_DUE_DATES_CORE] Hesaplama referans ayının gün aralığı alınamadı. Direkt card.dueDate (\(card.dueDate)) kullanılıyor.")
        }

        guard let thisMonthStatementDate = calendar.date(from: componentsForStatementMonth) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("""
                [CALC_DUE_DATES_CORE] HATA: Hesaplama referans ayı için hesap kesim tarihi oluşturulamadı.
                Bileşenler: Y: \(componentsForStatementMonth.year ?? -1) M: \(componentsForStatementMonth.month ?? -1) D: \(componentsForStatementMonth.day ?? -1)
                """)
            return []
        }
        logger.debug("[CALC_DUE_DATES_CORE] Hesaplama Referans Ayı İçin Hesap Kesim Tarihi: \(self.debugFormatter.string(from: thisMonthStatementDate))")

        guard let offsetAddedToStatement = calendar.date(byAdding: .day, value: card.paymentDueDaysOffset, to: thisMonthStatementDate) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("[CALC_DUE_DATES_CORE] HATA: \(self.debugFormatter.string(from: thisMonthStatementDate)) tarihine \(card.paymentDueDaysOffset) gün eklenemedi.")
            return []
        }
        logger.debug("[CALC_DUE_DATES_CORE] \(card.paymentDueDaysOffset) Gün Eklenmiş Ham Son Ödeme Tarihi: \(self.debugFormatter.string(from: offsetAddedToStatement))")
        
        let thisMonthCalculatedDueDate = holidayService.findNextWorkingDay(from: offsetAddedToStatement)
        logger.debug("[CALC_DUE_DATES_CORE] Hesaplama Referans Ayı İçin Son Ödeme Tarihi (iş günü): \(self.debugFormatter.string(from: thisMonthCalculatedDueDate))")

        let isPastPaymentComparedToOriginalInput = thisMonthCalculatedDueDate < comparisonReferenceDayStart
        let isTodayComparedToOriginalInput = calendar.isDate(thisMonthCalculatedDueDate, inSameDayAs: comparisonReferenceDayStart)

        // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
        logger.debug("""
            [CALC_DUE_DATES_CORE] Karşılaştırma (Orijinal Gelen Tarihe Göre):
            Hesaplanan Son Ödeme (Ref. Ay): \(self.debugFormatter.string(from: thisMonthCalculatedDueDate))
            Orijinal Gelen Referans Tarih (Karşılaştırma Noktası): \(self.debugFormatter.string(from: comparisonReferenceDayStart))
            Ödeme, Orijinal Gelen Ref. Tarihe Göre Geçmişte mi? \(isPastPaymentComparedToOriginalInput)
            Ödeme, Orijinal Gelen Ref. Tarih ile Aynı Gün mü? \(isTodayComparedToOriginalInput)
            """)

        if isTodayComparedToOriginalInput {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH ile aynı gün.")
            if let nextMonthDueDate = calculateFollowingMonthDueDate(
                currentYear: componentsForStatementMonth.year!,
                currentMonth: componentsForStatementMonth.month!,
                card: card,
                calendar: calendar,
                holidayService: holidayService
            ) {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                logger.info("""
                    [CALC_DUE_DATES_CORE] Sonuç: [Orijinal Ref. Tarihe Denk Gelen Ödeme, Sonraki Ay Ödemesi]
                    -> [\(self.debugFormatter.string(from: thisMonthCalculatedDueDate)), \(self.debugFormatter.string(from: nextMonthDueDate))]
                    """)
                return [thisMonthCalculatedDueDate, nextMonthDueDate].sorted()
            } else {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                logger.warning("[CALC_DUE_DATES_CORE] Sonraki ay ödeme tarihi hesaplanamadı. Sadece Orijinal Ref. Tarihe denk gelen ödeme döndürülüyor.")
                return [thisMonthCalculatedDueDate]
            }
        } else if isPastPaymentComparedToOriginalInput {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH'e göre GEÇMİŞTE.")
            if let nextMonthDueDate = calculateFollowingMonthDueDate(
                currentYear: componentsForStatementMonth.year!,
                currentMonth: componentsForStatementMonth.month!,
                card: card,
                calendar: calendar,
                holidayService: holidayService
            ) {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                logger.info("[CALC_DUE_DATES_CORE] Sonuç: [Sonraki Ay Ödemesi] -> [\(self.debugFormatter.string(from: nextMonthDueDate))]")
                return [nextMonthDueDate]
            } else {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                logger.error("[CALC_DUE_DATES_CORE] Ödeme geçmiş olmasına rağmen sonraki ay ödeme tarihi hesaplanamadı. Boş dizi döndürülüyor.")
                return []
            }
        } else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.info("[CALC_DUE_DATES_CORE] DURUM: Hesaplanan ödeme, FONKSİYONA GELEN ORİJİNAL REFERANS TARİH'e göre GELECEKTE.")
            logger.info("[CALC_DUE_DATES_CORE] Sonuç: [Mevcut Hesap Kesim Periyoduna Ait Ödeme] -> [\(self.debugFormatter.string(from: thisMonthCalculatedDueDate))]")
            return [thisMonthCalculatedDueDate]
        }
    }

    private static func calculateFollowingMonthDueDate(
        currentYear: Int,
        currentMonth: Int,
        card: CreditCard,
        calendar: Calendar,
        holidayService: HolidayService
    ) -> Date? {
        // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
        logger.debug("""
            [CALC_FOLLOWING_MONTH] Sonraki ay son ödeme tarihi hesaplaması başladı.
            Referans Yıl (Hesap Kesim Ayı İçin): \(currentYear), Referans Ay (Hesap Kesim Ayı İçin): \(currentMonth), Kartın Orijinal Kesim Günü: \(card.dueDate)
            """)

        var nextMonthStatementComponents = DateComponents()
        nextMonthStatementComponents.year = currentYear
        nextMonthStatementComponents.month = currentMonth + 1

        var tempDateForMonthRangeComponents = DateComponents(year: nextMonthStatementComponents.year, month: nextMonthStatementComponents.month, day: 1)

        guard let dateForFollowingMonthInfo = calendar.date(from: tempDateForMonthRangeComponents) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("""
            [CALC_FOLLOWING_MONTH] Sonraki ay için gün sayısı alınacak tarih oluşturulamadı.
            Bileşenler: Y:\(tempDateForMonthRangeComponents.year ?? -1) M:\(tempDateForMonthRangeComponents.month ?? -1)
            """)
            return nil
        }

        if let monthRange = calendar.range(of: .day, in: .month, for: dateForFollowingMonthInfo) {
            nextMonthStatementComponents.day = min(card.dueDate, monthRange.count)
            if card.dueDate > monthRange.count {
                // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
                 logger.warning("""
                    [CALC_FOLLOWING_MONTH] Kart hesap kesim günü (\(card.dueDate))
                    sonraki ayın (\(calendar.component(.month, from: dateForFollowingMonthInfo))/\(calendar.component(.year, from: dateForFollowingMonthInfo)))
                    gün sayısını (\(monthRange.count)) aşıyor.
                    Ayın son günü (\(nextMonthStatementComponents.day ?? 0)) kullanıldı.
                    """)
            }
        } else {
            nextMonthStatementComponents.day = card.dueDate
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("[CALC_FOLLOWING_MONTH] Sonraki ayın gün aralığı alınamadı. Direkt card.dueDate (\(card.dueDate)) kullanılıyor.")
        }

        guard let nextMonthStatementDate = calendar.date(from: nextMonthStatementComponents) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("""
                [CALC_FOLLOWING_MONTH] HATA: Sonraki ay için hesap kesim tarihi oluşturulamadı.
                Bileşenler: Y: \(nextMonthStatementComponents.year ?? -1) M: \(nextMonthStatementComponents.month ?? -1) D: \(nextMonthStatementComponents.day ?? -1)
                """)
            return nil
        }
        logger.debug("[CALC_FOLLOWING_MONTH] Sonraki Ay Hesap Kesim Tarihi: \(self.debugFormatter.string(from: nextMonthStatementDate))")
        
        guard let offsetAddedToNextMonthStatement = calendar.date(byAdding: .day, value: card.paymentDueDaysOffset, to: nextMonthStatementDate) else {
            // DÜZELTME: Log mesajı string interpolasyonu içine alındı.
            logger.error("[CALC_FOLLOWING_MONTH] HATA: \(self.debugFormatter.string(from: nextMonthStatementDate)) tarihine \(card.paymentDueDaysOffset) gün eklenemedi.")
            return nil
        }
        logger.debug("[CALC_FOLLOWING_MONTH] \(card.paymentDueDaysOffset) Gün Eklenmiş Ham Son Ödeme Tarihi (Sonraki Ay): \(self.debugFormatter.string(from: offsetAddedToNextMonthStatement))")

        let nextMonthCalculatedDueDate = holidayService.findNextWorkingDay(from: offsetAddedToNextMonthStatement)
        logger.debug("[CALC_FOLLOWING_MONTH] Sonraki Ay Son Ödeme Tarihi (iş günü): \(self.debugFormatter.string(from: nextMonthCalculatedDueDate))")
        return nextMonthCalculatedDueDate
    }
}
