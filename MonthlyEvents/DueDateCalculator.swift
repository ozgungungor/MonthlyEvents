import Foundation

struct DueDateCalculator {

    /// Bir kart için, referans tarihinden sonraki en yakın iki adet son ödeme tarihini bulur ve tatil günlerini atlayarak iş gününe denk getirir.
    /// Ancak abonelikler için tatil günü atlaması yapmaz.
    static func calculateDueDates(for card: CreditCard, referenceDate: Date = Date(), using holidayService: HolidayService) -> [Date] {
        let calendar = Calendar.current
        var dueDates: [Date] = []
        let today = calendar.startOfDay(for: referenceDate)
        
        var rawDueDates: [Date] = []
        
        // Ödeme tipine göre ham son ödeme tarihlerini bul
        if card.type == .loan {
            // Krediler için
            if let firstLoanDate = findNextSingleLoanDueDate(for: card, calendar: calendar, today: today) {
                rawDueDates.append(firstLoanDate)
                
                // Eğer ilk kredi ödeme tarihi bugünse veya geçmişteyse, bir sonraki taksiti de bul.
                if calendar.isDate(firstLoanDate, inSameDayAs: today) || firstLoanDate < today {
                    if let dayAfterFirstLoanDate = calendar.date(byAdding: .day, value: 1, to: firstLoanDate) {
                        if let secondLoanDate = findNextSingleLoanDueDate(for: card, calendar: calendar, today: dayAfterFirstLoanDate) {
                            rawDueDates.append(secondLoanDate)
                        }
                    }
                }
            }
        } else if card.type == .subscription {
            // Abonelikler için sonraki iki ödeme tarihini bul (Tatil veya hafta sonu kaydırması yapmaz)
            rawDueDates.append(contentsOf: findNextTwoSubscriptionDueDates(for: card, calendar: calendar, today: today))
            
            // Abonelikler için doğrudan ham tarihleri kullanacağız, kaydırma yapmayacağız.
            // Sadece ilk ödeme tarihi bugünse iki tarih döndürelim, değilse sadece bir tarih.
            var finalSubscriptionDates = rawDueDates.sorted()
            if finalSubscriptionDates.first.map({ calendar.isDate($0, inSameDayAs: today) }) == true && finalSubscriptionDates.count > 1 {
                return Array(finalSubscriptionDates.prefix(2))
            } else if let firstDate = finalSubscriptionDates.first {
                return [firstDate]
            } else {
                return []
            }

        } else { // Kart ve Tek Seferlik Ödeme
            if let firstRawDueDate = findNextSingleCardOrOneTimeDueDate(for: card, calendar: calendar, today: today) {
                rawDueDates.append(firstRawDueDate)
                
                // YENİ MANTIK: Sadece ilk ödeme tarihi bugünse veya geçmişte ise ve kart tipi TEK SEFERLİK ÖDEME DEĞİLSE ikinci tarihi ara
                // Yani, eğer ilk ödeme bugünse (veya önceki bir tarihten dolayı kaydırıldıysa), bir sonraki ödeme tarihini de göster.
                // Aksi takdirde sadece ilk ödeme tarihini göster.
                if card.type == .card && (calendar.isDate(firstRawDueDate, inSameDayAs: today) || firstRawDueDate < today) {
                    if let dayAfterFirstDueDate = calendar.date(byAdding: .day, value: 1, to: firstRawDueDate) {
                        if let secondRawDueDate = findNextSingleCardOrOneTimeDueDate(for: card, calendar: calendar, today: dayAfterFirstDueDate) {
                            rawDueDates.append(secondRawDueDate)
                        }
                    }
                }
            }
        }

        // Ham tarihleri iş gününe kaydır ve benzersizlerini al (Sadece Kredi ve Tek Seferlik Ödemeler için geçerli)
        var finalDueDates: [Date] = []
        for rawDate in rawDueDates {
            let workingDay = holidayService.findNextWorkingDay(from: rawDate)
            if !finalDueDates.contains(where: { calendar.isDate($0, inSameDayAs: workingDay) }) {
                finalDueDates.append(workingDay)
            }
        }
        
        // Şimdi sadece ilk ödeme tarihi bugünse iki tarih döndürelim, değilse sadece bir tarih.
        // ANCAK TEK SEFERLİK ÖDEMELER İÇİN HER ZAMAN SADECE BİR TARİH DÖNDÜR.
        if card.type == .oneTimePayment {
            return finalDueDates.prefix(1).sorted()
        } else if finalDueDates.first.map({ calendar.isDate($0, inSameDayAs: today) }) == true && finalDueDates.count > 1 {
            // İlk tarih bugünse ve ikinci tarih varsa, ikisini de döndür
            return Array(finalDueDates.prefix(2)).sorted()
        } else if let firstDate = finalDueDates.first {
            // İlk tarih bugün değilse veya tek tarih varsa, sadece onu döndür
            return [firstDate].sorted()
        } else {
            return []
        }
    }

    /// Bir kart veya tek seferlik ödeme için bugünden sonraki en yakın tek bir ham son ödeme tarihini bulur.
    private static func findNextSingleCardOrOneTimeDueDate(for card: CreditCard, calendar: Calendar, today: Date) -> Date? {
        var monthOffset = 0
        while monthOffset < 24 { // Sonsuz döngü koruması
            // Gelecek ayları tek tek kontrol et
            guard let baseDate = calendar.date(byAdding: .month, value: monthOffset, to: today) else {
                monthOffset += 1
                continue
            }
            
            var components = calendar.dateComponents([.year, .month], from: baseDate)
            
            // Ayın gün sayısını kontrol ederek güvenli gün ata (örn: 31 şubat hatasını engelle)
            guard let monthForDayCheck = calendar.date(from: components),
                  let monthRange = calendar.range(of: .day, in: .month, for: monthForDayCheck) else {
                monthOffset += 1
                continue
            }
            components.day = min(card.dueDate, monthRange.count)
            
            guard var initialDate = calendar.date(from: components) else {
                monthOffset += 1
                continue
            }
            
            // Kredi kartları için "eklenecek gün" (offset) değerini uygula
            if card.type == .card {
                initialDate = calendar.date(byAdding: .day, value: card.paymentDueDaysOffset, to: initialDate) ?? initialDate
            }

            // Eğer hesaplanan tarih, aramanın başlangıç tarihinden sonraysa veya aynı günse, onu bulduk demektir.
            if initialDate >= today {
                return initialDate
            }
            
            // Eğer hesaplanan tarih geçmişte kaldıysa, bir sonraki ayı denemek için döngüye devam et.
            // Bu durum genellikle ilk aydan sonraki aylar için geçerlidir.
            monthOffset += 1
        }
        
        return nil
    }

    /// Kredi kartları için bir sonraki taksit ödeme tarihini bulur.
    private static func findNextSingleLoanDueDate(for card: CreditCard, calendar: Calendar, today: Date) -> Date? {
        guard card.type == .loan,
              let totalInstallments = card.totalInstallments,
              let remainingInstallments = card.remainingInstallments,
              remainingInstallments > 0,
              let creationDate = card.creationDate else {
            return nil
        }
        
        // Zaten ödenmiş taksit sayısını bul
        let paymentsMade = totalInstallments - remainingInstallments

        // Başlangıç tarihi olarak kartın oluşturulma tarihini al
        var searchDate = creationDate
        
        // Bugünün tarihinden sonraki ilk taksit tarihini bulmaya çalış
        for _ in 0..<(remainingInstallments + 2) { // Yeterli sayıda ay kontrolü
            var components = calendar.dateComponents([.year, .month], from: searchDate)
            components.day = card.dueDate
            
            guard let potentialDueDate = calendar.date(from: components) else {
                searchDate = calendar.date(byAdding: .month, value: 1, to: searchDate) ?? searchDate
                continue
            }

            // Eğer potansiyel ödeme tarihi bugünden sonra veya bugünse
            if potentialDueDate >= today {
                return potentialDueDate
            }
            
            // Bir sonraki aya geç
            searchDate = calendar.date(byAdding: .month, value: 1, to: searchDate) ?? searchDate
        }
        
        return nil
    }

    /// Abonelikler için sonraki iki ödeme tarihini bulur. (Tatil veya hafta sonu kaydırması yapmaz)
    private static func findNextTwoSubscriptionDueDates(for card: CreditCard, calendar: Calendar, today: Date) -> [Date] {
        guard card.type == .subscription else { return [] }

        var foundDates: [Date] = []
        var searchDate = calendar.startOfDay(for: today) // Aramaya bugünden başla

        for _ in 0..<36 { // Yeterli sayıda ay/yıl kontrolü (örn: 3 yıl)
            var components = calendar.dateComponents([.year, .month], from: searchDate)
            
            // Abonelik tipi yıllık ise, belirtilen ayı kullan
            if card.billingCycle == .annually, let annualMonth = card.annualBillingMonth {
                components.month = annualMonth
                // Yıl değişebilir, eğer current searchDate'in ayı annualMonth'tan büyükse sonraki yıla geç
                if let currentMonth = calendar.dateComponents([.month], from: searchDate).month,
                   let currentYear = calendar.dateComponents([.year], from: searchDate).year {
                    
                    if currentMonth > annualMonth {
                        components.year = currentYear + 1
                    } else if currentMonth == annualMonth && card.dueDate < calendar.component(.day, from: today) && currentYear == calendar.component(.year, from: today) {
                        components.year = currentYear + 1
                    }
                }
            }
            
            // Ayın gün sayısını kontrol ederek güvenli gün ata
            guard let monthForDayCheck = calendar.date(from: components),
                  let monthRange = calendar.range(of: .day, in: .month, for: monthForDayCheck) else {
                // Eğer tarih geçerli değilse, bir sonraki arama noktasına geç
                if card.billingCycle == .annually {
                    searchDate = calendar.date(byAdding: .year, value: 1, to: searchDate) ?? searchDate
                } else {
                    searchDate = calendar.date(byAdding: .month, value: 1, to: searchDate) ?? searchDate
                }
                continue
            }
            components.day = min(card.dueDate, monthRange.count)

            guard let potentialDueDate = calendar.date(from: components) else {
                // Eğer tarih geçerli değilse, bir sonraki arama noktasına geç
                if card.billingCycle == .annually {
                    searchDate = calendar.date(byAdding: .year, value: 1, to: searchDate) ?? searchDate
                } else {
                    searchDate = calendar.date(byAdding: .month, value: 1, to: searchDate) ?? searchDate
                }
                continue
            }

            if potentialDueDate >= today {
                // Eğer bu tarih bugünden sonra veya bugün ise ve daha önce eklenmemişse ekle
                if !foundDates.contains(where: { calendar.isDate($0, inSameDayAs: potentialDueDate) }) {
                    foundDates.append(potentialDueDate)
                    // Abonelikler için her zaman 2 tarih döndürmek istiyoruz
                    if foundDates.count == 2 { break }
                }
            }
            
            // Bir sonraki arama noktasına geç
            if card.billingCycle == .annually {
                searchDate = calendar.date(byAdding: .year, value: 1, to: searchDate) ?? searchDate
            } else { // monthly
                searchDate = calendar.date(byAdding: .month, value: 1, to: searchDate) ?? searchDate
            }
        }
        
        return foundDates.sorted()
    }
}
