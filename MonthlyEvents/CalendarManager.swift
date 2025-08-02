import EventKit
import SwiftUI
import os.log

private struct EventConstants {
    static let alarmOffset: TimeInterval = -9 * 3600
    static let startHour = 9
    static let endHour = 12
}

class CalendarManager {
    static let shared = CalendarManager()
    private let eventStore = EKEventStore()
    private var appCalendar: EKCalendar?
    
    private let calendarIdentifierKey = "appCalendarIdentifier"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CalendarManager")

    // MARK: - Calendar Management

    // 1. ADIM: Takvim başlığını yerelleştirme yerine sabit olarak "Paynify" yapıyoruz.
    private var calendarTitle: String {
        return "Paynify" // GÜNCELLENDİ
    }

    private var calendar: EKCalendar? {
        if let cachedCalendar = appCalendar, eventStore.calendar(withIdentifier: cachedCalendar.calendarIdentifier) != nil {
            return cachedCalendar
        }

        if let identifier = UserDefaults.standard.string(forKey: calendarIdentifierKey),
           let foundCalendar = eventStore.calendar(withIdentifier: identifier) {
            self.appCalendar = foundCalendar
            return foundCalendar
        }

        // 2. ADIM: Birden çok olası başlık yerine sadece "Paynify" adında bir takvim arıyoruz.
        // Not: Eski isimleri de bulup silmesi için reset fonksiyonundaki liste kalabilir.
        if let existingCalendar = eventStore.calendars(for: .event).first(where: { $0.title == self.calendarTitle }) { // GÜNCELLENDİ
            UserDefaults.standard.set(existingCalendar.calendarIdentifier, forKey: calendarIdentifierKey)
            self.appCalendar = existingCalendar
            return existingCalendar
        }

        if let newCalendar = createCalendar(withTitle: self.calendarTitle) {
            self.appCalendar = newCalendar
            return newCalendar
        }
        
        return nil
    }

    private init() {}

    public func resetAndCreateNewCalendar(for locale: Locale) {
        logger.warning("Starting a hard reset of calendars. ALL EVENTS in related calendars will be DELETED.")
        
        // Bu liste eski sürümlerden kalma takvimleri bulup silmek için geniş tutulabilir.
        let possibleTitles = ["Payment Reminders", "Ödeme Hatırlatmaları", "App Payments", "Paynify"]
        var calendarsToDelete: [EKCalendar] = []
        let allCalendars = eventStore.calendars(for: .event)
        
        calendarsToDelete.append(contentsOf: allCalendars.filter { possibleTitles.contains($0.title) })
        
        if let identifier = UserDefaults.standard.string(forKey: calendarIdentifierKey),
           let calendarById = allCalendars.first(where: { $0.calendarIdentifier == identifier }) {
            if !calendarsToDelete.contains(where: { $0.calendarIdentifier == calendarById.calendarIdentifier }) {
                calendarsToDelete.append(calendarById)
            }
        }
        
        for calendar in Set(calendarsToDelete) {
            do {
                logger.warning("DELETING calendar: '\(calendar.title)' and all its events.")
                try eventStore.removeCalendar(calendar, commit: true)
            } catch {
                logger.error("Failed to delete calendar '\(calendar.title)': \(error.localizedDescription)")
            }
        }
        
        UserDefaults.standard.removeObject(forKey: calendarIdentifierKey)
        self.appCalendar = nil // Önbelleği temizle
        logger.info("Finished hard reset. Old identifier cleared.")
        
        // 3. ADIM: Sıfırlama sonrası yeni takvim oluşturulurken, dil ayarından bağımsız olarak "Paynify" adını kullan.
        let newTitle = self.calendarTitle // GÜNCELLENDİ
        _ = self.createCalendar(withTitle: newTitle)
    }

    private func createCalendar(withTitle title: String) -> EKCalendar? {
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = title
        
        if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased() == "icloud" }) {
            newCalendar.source = iCloudSource
        } else {
            newCalendar.source = eventStore.defaultCalendarForNewEvents?.source ?? eventStore.sources.first { $0.sourceType == .local }
        }
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            UserDefaults.standard.set(newCalendar.calendarIdentifier, forKey: calendarIdentifierKey)
            logger.info("New calendar created: '\(title)'")
            return newCalendar
        } catch {
            logger.error("Failed to create new calendar: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Access Management
    func requestAccessIfNeeded() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            do {
                if #available(iOS 17.0, *) {
                    return try await eventStore.requestFullAccessToEvents()
                } else {
                    return try await eventStore.requestAccess(to: .event)
                }
            } catch {
                logger.error("Calendar access request error: \(error.localizedDescription)")
                return false
            }
        default:
            return false
        }
    }
    
    // MARK: - Event Management
    func addOrUpdateEvents(for card: CreditCard, dueDates: [Date], holidayService: HolidayService, locale: Locale) {
        guard let eventCalendar = calendar else {
            logger.warning("Calendar not found. Events cannot be saved.")
            return
        }
        
        self.removeAllEvents(for: card)
        
        guard card.isActive else {
            logger.info("Card '\(card.name)' is inactive. No new events will be created.")
            return
        }
        
        var eventsToSave: [EKEvent] = []
        for (index, dueDate) in dueDates.enumerated() {
            if let newEvent = createEvent(for: card, dueDate: dueDate, index: index, in: eventCalendar, locale: locale) {
                eventsToSave.append(newEvent)
            }
        }
        
        if !eventsToSave.isEmpty {
            do {
                for event in eventsToSave {
                    try eventStore.save(event, span: .thisEvent)
                }
                try eventStore.commit()
                logger.info("Successfully saved \(eventsToSave.count) new events for card '\(card.name)'.")
            } catch {
                logger.error("Failed to commit new event creations: \(error.localizedDescription)")
            }
        }
    }

    /// Uygulamanın takvimindeki tüm etkinlikleri siler.
    func removeAllAppEvents() {
        guard let eventCalendar = calendar else {
            logger.warning("Takvim bulunamadı. Etkinlikler silinemiyor.")
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: .distantPast, end: .distantFuture, calendars: [eventCalendar])
        let events = eventStore.events(matching: predicate)

        guard !events.isEmpty else {
            logger.info("Uygulama takviminde silinecek etkinlik bulunamadı.")
            return
        }

        do {
            for event in events {
                try eventStore.remove(event, span: .thisEvent, commit: false)
            }
            try eventStore.commit()
            logger.info("Uygulama takvimindeki \(events.count) adet etkinliğin tümü başarıyla kaldırıldı.")
        } catch {
            logger.error("Takvimdeki tüm etkinlikler silinirken hata oluştu: \(error.localizedDescription)")
        }
    }
    
    func removeAllEvents(for card: CreditCard) {
        guard let eventCalendar = calendar else { return }
        let events = findEvents(for: card, in: eventCalendar)
        guard !events.isEmpty else { return }
        
        for event in events {
            do { try eventStore.remove(event, span: .thisEvent) } catch { logger.error("Failed to remove an event: \(error.localizedDescription)") }
        }
        do {
            try eventStore.commit()
            logger.info("Removed \(events.count) events for card '\(card.name)'.")
        } catch {
            logger.error("Failed to commit event removal: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Functions
    private func findEvents(for card: CreditCard, in calendar: EKCalendar) -> [EKEvent] {
        let identifierTag = "PAYMENT-ID: \(card.id.uuidString)"
        let predicate = eventStore.predicateForEvents(withStart: .distantPast, end: .distantFuture, calendars: [calendar])
        return eventStore.events(matching: predicate).filter { $0.notes?.contains(identifierTag) == true }
    }
    
    func findEventsForDate(_ date: Date) -> [EKEvent] {
        guard let eventCalendar = calendar else { return [] }
        
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: date)
        guard let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) else { return [] }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [eventCalendar])
        
        return eventStore.events(matching: predicate)
    }

    private func createEvent(for card: CreditCard, dueDate: Date, index: Int, in calendar: EKCalendar, locale: Locale) -> EKEvent? {
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.notes = "PAYMENT-ID: \(card.id.uuidString)"
        event.url = URL(string: "paynify://open/item/\(card.id.uuidString)")
        
        event.addAlarm(EKAlarm(relativeOffset: EventConstants.alarmOffset))
        
        update(event: event, for: card, dueDate: dueDate, index: index, locale: locale)
        return event
    }

    private func update(event: EKEvent, for card: CreditCard, dueDate: Date, index: Int, locale: Locale) {
        switch card.type {
        case .card:
            event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_CARD", locale: locale), card.name)
        case .loan:
            if let total = card.totalInstallments, let remaining = card.remainingInstallments {
                let paymentsMade = total - remaining
                let currentInstallment = paymentsMade + index + 1
                event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_LOAN", locale: locale), card.name, currentInstallment, total)
            } else {
                event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_LOAN_SIMPLE", locale: locale), card.name)
            }
        case .oneTimePayment:
            event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_ONETIME", locale: locale), card.name)
        case .subscription: // YENİ
            if card.billingCycle == .annually, let month = card.annualBillingMonth {
                event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_SUBSCRIPTION_ANNUAL", locale: locale), card.name, localizedMonthName(month: month, locale: locale))
            } else {
                event.title = String(format: localizedString(forKey: "CALENDAR_EVENT_TITLE_SUBSCRIPTION_MONTHLY", locale: locale), card.name)
            }
        }
        
        let calendar = Calendar.current
        var startComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)
        startComponents.hour = EventConstants.startHour
        var endComponents = startComponents
        endComponents.hour = EventConstants.endHour

        if let eventStartDate = calendar.date(from: startComponents),
           let eventEndDate = calendar.date(from: endComponents) {
            event.startDate = eventStartDate
            event.endDate = eventEndDate
        }
        event.isAllDay = false
    }

    private func localizedString(forKey key: String, locale: Locale) -> String {
        if let langCode = locale.language.languageCode?.identifier,
           let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: nil, bundle: bundle, comment: "")
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
