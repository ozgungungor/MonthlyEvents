import SwiftUI
import EventKit
import os.log

class HolidayService: ObservableObject {
    static let shared = HolidayService()

    private let eventStore = EKEventStore()
    @Published var hasCalendarAccess = false
    
    // Kullanıcının ayarladığı hafta sonu günleri
    @AppStorage("isMondayHoliday") private var isMondayHoliday: Bool = false
    @AppStorage("isTuesdayHoliday") private var isTuesdayHoliday: Bool = false
    @AppStorage("isWednesdayHoliday") private var isWednesdayHoliday: Bool = false
    @AppStorage("isThursdayHoliday") private var isThursdayHoliday: Bool = false
    @AppStorage("isFridayHoliday") private var isFridayHoliday: Bool = false
    @AppStorage("isSaturdayHoliday") private var isSaturdayHoliday: Bool = true
    @AppStorage("isSundayHoliday") private var isSundayHoliday: Bool = true

    // Tatil olarak kabul edilecek anahtar kelimeler
    @AppStorage("customHolidayKeywords") private var customHolidayKeywordsString: String = "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival"

    // Seçilen takvimlerin ID'lerini saklamak için @AppStorage
    // Dizi doğrudan saklanamadığı için JSON olarak kodlayıp saklayacağız.
    @AppStorage("selectedCalendarIDs") private var selectedCalendarIDsJSON: String = ""

    private var holidayKeywords: [String] {
        customHolidayKeywordsString.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    private let debugFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss Z (EEEE)"
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
    
    // MARK: - Calendar Management
    
    /// Cihazdaki tüm takvim kaynaklarını döndürür. Ayarlar ekranında kullanılmak üzere.
    func getAvailableCalendars() -> [EKCalendar] {
        guard hasCalendarAccess else { return [] }
        return eventStore.calendars(for: .event)
    }
    
    /// Kullanıcının seçtiği takvim ID'lerini kaydeder.
    func saveSelectedCalendarIDs(_ ids: [String]) {
        if let data = try? JSONEncoder().encode(ids), let jsonString = String(data: data, encoding: .utf8) {
            selectedCalendarIDsJSON = jsonString
            logger.info("Seçilen takvim ID'leri kaydedildi.")
            // Seçim değiştiğinde arayüzü yenilemek için sinyal gönder
            self.refresh()
        }
    }
    
    /// Kaydedilmiş takvim ID'lerini yükler.
    func loadSelectedCalendarIDs() -> [String] {
        if let data = selectedCalendarIDsJSON.data(using: .utf8),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids
        }
        // Eğer hiç seçim yapılmamışsa, tüm takvimleri varsayılan olarak seçili yap.
        let allCalendarIDs = getAvailableCalendars().map { $0.calendarIdentifier }
        // Başlangıçta kaydetmek için save'i çağır
        if !allCalendarIDs.isEmpty && selectedCalendarIDsJSON.isEmpty {
           saveSelectedCalendarIDs(allCalendarIDs)
        }
        return allCalendarIDs
    }
    
    // MARK: - Holiday Calculation Logic

    /// Bir tarihin neden tatil olduğunu (eğer tatilse) string olarak döndürür.
    private func getHolidayReason(for date: Date) -> String? {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        
        // 1. Kullanıcının ayarladığı hafta sonu günlerini kontrol et
        if let weekendReason = getUserDefinedWeekendReason(date: normalizedDate) {
            return "Kullanıcı tanımlı hafta sonu: \(weekendReason)"
        }
        
        // 2. Takvim etkinliklerini kontrol et (eğer erişim varsa)
        if hasCalendarAccess {
            if let calendarReason = getCalendarHolidayReason(date: normalizedDate) {
                return "Takvim etkinliği: '\(calendarReason)'"
            }
        }
        
        // Tatil değilse nil döndür
        return nil
    }

    /// Bir günün kullanıcı tanımlı hafta sonu olup olmadığını ve gün adını döndürür.
    private func getUserDefinedWeekendReason(date: Date) -> String? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // 1=Pazar, 2=Pazartesi, ..., 7=Cumartesi
        
        let dayName: String
        let isHoliday: Bool
        
        switch weekday {
        case 1: (dayName, isHoliday) = ("Pazar", isSundayHoliday)
        case 2: (dayName, isHoliday) = ("Pazartesi", isMondayHoliday)
        case 3: (dayName, isHoliday) = ("Salı", isTuesdayHoliday)
        case 4: (dayName, isHoliday) = ("Çarşamba", isWednesdayHoliday)
        case 5: (dayName, isHoliday) = ("Perşembe", isThursdayHoliday)
        case 6: (dayName, isHoliday) = ("Cuma", isFridayHoliday)
        case 7: (dayName, isHoliday) = ("Cumartesi", isSaturdayHoliday)
        default: return nil
        }
        
        return isHoliday ? dayName : nil
    }
    
    /// Bir günün takvim etkinliği nedeniyle tatil olup olmadığını ve etkinlik başlığını döndürür.
    private func getCalendarHolidayReason(date: Date) -> String? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }
        
        // 1. Kullanıcının seçtiği takvimleri al
        let selectedIDs = Set(loadSelectedCalendarIDs())
        let calendarsToSearch = getAvailableCalendars().filter { selectedIDs.contains($0.calendarIdentifier) }

        // 2. Eğer kullanıcı hiçbir takvim seçmemişse (veya erişim yoksa) arama yapma
        guard !calendarsToSearch.isEmpty else {
            logger.debug("[getCalendarHolidayReason] Aranacak seçili takvim bulunmuyor.")
            return nil
        }
        
        // 3. Predicate'i `nil` yerine sadece seçili takvimlerle oluştur
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendarsToSearch)
        let events = eventStore.events(matching: predicate)
        
        for event in events {
            if event.isAllDay {
                let title = event.title ?? ""
                if isHolidayKeyword(in: title) {
                    // Tatil sebebi olarak etkinliğin başlığını döndür
                    return title
                }
            }
        }
        return nil
    }
    
    private func isHolidayKeyword(in title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        for keyword in holidayKeywords {
            if lowercasedTitle.contains(keyword) {
                return true
            }
        }
        return false
    }
    
    func findNextWorkingDay(from date: Date) -> Date {
        let calendar = Calendar.current
        var nextDay = calendar.startOfDay(for: date)
        logger.info("[FIND_NEXT_WORKING_DAY] Başlangıç tarihi (normalize edilmiş): \(self.debugFormatter.string(from: nextDay))")

        var daysChecked = 0
        let maxDaysToCheck = 30

        while let reason = getHolidayReason(for: nextDay), daysChecked < maxDaysToCheck {
            logger.debug("[FIND_NEXT_WORKING_DAY] Tarih kaydırıldı: \(self.debugFormatter.string(from: nextDay)). Sebep: \(reason)")
            
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
            
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }
}
