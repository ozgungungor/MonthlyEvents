import SwiftUI
import EventKit
import os.log

class HolidayService: ObservableObject {
    static let shared = HolidayService()

    private let eventStore = EKEventStore()
    @Published var hasCalendarAccess = false
    
    // Kullanıcı tercihleri için AppStorage
    @AppStorage("isMondayHoliday") private var isMondayHoliday: Bool = false
    @AppStorage("isTuesdayHoliday") private var isTuesdayHoliday: Bool = false
    @AppStorage("isWednesdayHoliday") private var isWednesdayHoliday: Bool = false
    @AppStorage("isThursdayHoliday") private var isThursdayHoliday: Bool = false
    @AppStorage("isFridayHoliday") private var isFridayHoliday: Bool = false
    @AppStorage("isSaturdayHoliday") private var isSaturdayHoliday: Bool = true
    @AppStorage("isSundayHoliday") private var isSundayHoliday: Bool = true

    @AppStorage("customHolidayKeywords") private var customHolidayKeywordsString: String = "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival"

    // Anahtar kelimeler dizisi (computed property ile güncel kalır)
    private var holidayKeywords: [String] {
        customHolidayKeywordsString.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private let debugFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z (EEEE)" // Gün adını da ekledim
        df.locale = Locale(identifier: "tr_TR")
        return df
    }()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HolidayService")

    private init() {}

    func requestCalendarAccess() async -> Bool {
        logger.info("[REQUEST_ACCESS] Takvim erişim durumu kontrol ediliyor.")
        let status = EKEventStore.authorizationStatus(for: .event)
        
        var granted = false
        switch status {
        case .authorized, .fullAccess:
            logger.info("[REQUEST_ACCESS] Erişim zaten var (authorized/fullAccess).")
            granted = true
        case .notDetermined:
            logger.info("[REQUEST_ACCESS] Erişim durumu belirsiz (notDetermined), izin isteniyor.")
            do {
                if #available(iOS 17.0, *) {
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await eventStore.requestAccess(to: .event)
                }
                logger.info("[REQUEST_ACCESS] İzin isteği sonucu: \(granted ? "Verildi" : "Reddedildi")")
            } catch {
                logger.error("[REQUEST_ACCESS] Takvim erişim izni isteği başarısız: \(error.localizedDescription)")
                granted = false
            }
        case .denied, .restricted, .writeOnly:
            logger.warning("[REQUEST_ACCESS] Erişim reddedilmiş veya kısıtlı (denied/restricted/writeOnly).")
            granted = false
        @unknown default:
            logger.error("[REQUEST_ACCESS] Bilinmeyen takvim erişim durumu.")
            granted = false
        }
        
        await MainActor.run {
            self.hasCalendarAccess = granted
        }
        return granted
    }
    
    private func isHoliday(date: Date) -> Bool {
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: date)
        logger.debug("[IS_HOLIDAY] Kontrol edilen normalize edilmiş tarih: \(self.debugFormatter.string(from: normalizedDate))")

        // Kullanıcının haftalık tatil tercihine göre kontrol
        if isUserDefinedWeekend(date: normalizedDate) {
            logger.debug("[IS_HOLIDAY] \(self.debugFormatter.string(from: normalizedDate)) -> Kullanıcı Tanımlı Hafta İçi Tatili: EVET")
            return true
        }
        
        if isBasicTurkishHoliday(date: normalizedDate) { // Mevcut temel tatil listesi
            logger.debug("[IS_HOLIDAY] \(self.debugFormatter.string(from: normalizedDate)) -> Temel Türk Tatili: EVET")
            return true
        }

        if hasCalendarAccess {
            if isCalendarHoliday(date: normalizedDate) { // Kullanıcı takvimindeki etkinlikler
                logger.debug("[IS_HOLIDAY] \(self.debugFormatter.string(from: normalizedDate)) -> Kullanıcı Takvim Tatili: EVET")
                return true
            }
        } else {
            logger.debug("[IS_HOLIDAY] Takvim erişimi yok, isCalendarHoliday atlandı.")
        }
        
        logger.debug("[IS_HOLIDAY] \(self.debugFormatter.string(from: normalizedDate)) -> Tatil Değil.")
        return false
    }

    private func isUserDefinedWeekend(date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // 1=Pazar, 2=Pazartesi, ..., 7=Cumartesi

        switch weekday {
        case 1: return isSundayHoliday
        case 2: return isMondayHoliday
        case 3: return isTuesdayHoliday
        case 4: return isWednesdayHoliday
        case 5: return isThursdayHoliday
        case 6: return isFridayHoliday
        case 7: return isSaturdayHoliday
        default: return false
        }
    }
    
    private func isCalendarHoliday(date: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            logger.error("[IS_CALENDAR_HOLIDAY] Gün sonu hesaplanamadı: \(self.debugFormatter.string(from: startOfDay))")
            return false
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        logger.debug("[IS_CALENDAR_HOLIDAY] \(self.debugFormatter.string(from: startOfDay)) için \(events.count) etkinlik bulundu.")

        for event in events {
            if event.isAllDay {
                let title = event.title?.lowercased() ?? ""
                logger.debug("[IS_CALENDAR_HOLIDAY] Tam gün etkinlik başlığı: '\(title)'")
                if isHolidayKeyword(in: title) {
                    logger.debug("[IS_CALENDAR_HOLIDAY] Tatil anahtar kelimesi bulundu: '\(title)'")
                    return true
                }
            }
        }
        return false
    }
    
    private func isHolidayKeyword(in title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        for keyword in holidayKeywords { // Kullanıcının tanımladığı anahtar kelimeleri kullan
            if lowercasedTitle.contains(keyword) {
                return true
            }
        }
        return false
    }
    
    private func isBasicTurkishHoliday(date: Date) -> Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .year], from: calendar.startOfDay(for: date))
        
        guard let month = components.month, let day = components.day, let year = components.year else {
            logger.error("[IS_BASIC_TURKISH_HOLIDAY] Ay/gün/yıl bileşenleri alınamadı: \(self.debugFormatter.string(from: date))")
            return false
        }
        
        // Örnek 2024 Dini Bayramlar (Bu kısım dinamik bir API'den veya güncel bir listeden gelmeli)
        let dynamicHolidays: [(month: Int, day: Int, year: Int)] = [
            (4,10,2024), (4,11,2024), (4,12,2024), // Ramazan Bayramı
            (6,15,2024), // Kurban Bayramı Arefe
            (6,16,2024), (6,17,2024), (6,18,2024), (6,19,2024) // Kurban Bayramı
        ]
        
        if dynamicHolidays.contains(where: { $0.year == year && $0.month == month && $0.day == day }) {
            logger.debug("[IS_BASIC_TURKISH_HOLIDAY] Dinamik tatil (Örnek \(year)): Ay \(month), Gün \(day)")
            return true
        }

        let fixedHolidays: [(month: Int, day: Int)] = [
            (1, 1),  // Yılbaşı
            (4, 23), // Ulusal Egemenlik ve Çocuk Bayramı
            (5, 1),  // Emek ve Dayanışma Günü
            (5, 19), // Atatürk'ü Anma, Gençlik ve Spor Bayramı
            (7, 15), // Demokrasi ve Milli Birlik Günü
            (8, 30), // Zafer Bayramı
            (10, 29) // Cumhuriyet Bayramı (28 Ekim öğleden sonra, 29 Ekim tam gün)
        ]
        
        if fixedHolidays.contains(where: { $0.month == month && $0.day == day }) {
            logger.debug("[IS_BASIC_TURKISH_HOLIDAY] Sabit tatil: Ay \(month), Gün \(day)")
            return true
        }
        return false
    }
    
    func findNextWorkingDay(from date: Date) -> Date {
        let calendar = Calendar.current
        var nextDay = calendar.startOfDay(for: date)
        logger.info("[FIND_NEXT_WORKING_DAY] Başlangıç tarihi (normalize edilmiş): \(self.debugFormatter.string(from: nextDay))")

        var daysChecked = 0
        let maxDaysToCheck = 30

        while isHoliday(date: nextDay) && daysChecked < maxDaysToCheck {
            logger.debug("[FIND_NEXT_WORKING_DAY] Kontrol: \(self.debugFormatter.string(from: nextDay)) bir tatil. Sonraki güne geçiliyor.")
            guard let newCalculatedDay = calendar.date(byAdding: .day, value: 1, to: nextDay) else {
                logger.critical("[FIND_NEXT_WORKING_DAY] KRİTİK HATA: Sonraki güne ekleme yapılamadı! Mevcut gün: \(self.debugFormatter.string(from: nextDay)). Mevcut günü döndürüyorum.")
                return nextDay
            }
            nextDay = newCalculatedDay
            daysChecked += 1
        }
        
        if daysChecked >= maxDaysToCheck {
            logger.warning("[FIND_NEXT_WORKING_DAY] UYARI: maxDaysToCheck (\(maxDaysToCheck)) sınırına ulaşıldı. Döndürülen tarih: \(self.debugFormatter.string(from: nextDay))")
        }
        
        logger.info("[FIND_NEXT_WORKING_DAY] Bulunan sonraki iş günü: \(self.debugFormatter.string(from: nextDay))")
        return nextDay
    }

    func refresh() {
        Task {
            _ = await requestCalendarAccess()
            logger.info("[REFRESH] HolidayService yenilendi, takvim erişimi: \(self.hasCalendarAccess)")
        }
    }
}
