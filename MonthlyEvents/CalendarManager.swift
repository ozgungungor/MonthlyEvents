import EventKit

class CalendarManager {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    private let calendarTitle = "Kart Hatırlatmaları"
    
    private var calendar: EKCalendar? {
        eventStore.calendars(for: .event).first(where: { $0.title == calendarTitle })
    }

    private init() {
        if calendar == nil {
            createCalendarIfNeeded()
        }
    }
    
    private func createCalendarIfNeeded() {
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = calendarTitle
        newCalendar.source = eventStore.defaultCalendarForNewEvents?.source ??
                             eventStore.sources.first { $0.sourceType == .local }
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            print("Takvim oluşturuldu: \(calendarTitle)")
        } catch {
            print("Takvim oluşturulamadı: \(error.localizedDescription)")
        }
    }

    func requestAccessIfNeeded() async -> Bool {
        do {
            return try await eventStore.requestAccess(to: .event)
        } catch {
            print("Takvim erişim hatası: \(error.localizedDescription)")
            return false
        }
    }

    /// Etkinliği siler ve tekrar ekler (aynı etkinliğin çoğalmasını engeller)
    func addOrUpdateEvent(for card: CreditCard, dueDate: Date) {
        guard let eventCalendar = calendar else {
            print("Takvim bulunamadı.")
            return
        }

        let identifierTag = "CARD-ID: \(card.id.uuidString)"

        // 1. Mevcut etkinlikleri temizle
        let predicate = eventStore.predicateForEvents(
            withStart: Date().addingTimeInterval(-60*60*24*365),
            end: Date().addingTimeInterval(60*60*24*365),
            calendars: [eventCalendar]
        )

        let events = eventStore.events(matching: predicate)
        for event in events {
            if event.notes?.contains(identifierTag) == true || event.url?.absoluteString.contains(card.id.uuidString) == true {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                    print("Önceki etkinlik silindi: \(event.title ?? "")")
                } catch {
                    print("Önceki etkinlik silinemedi: \(error.localizedDescription)")
                }
            }
        }

        // 2. Yeni etkinliği ekle (saat 09:00–12:00)
        let event = EKEvent(eventStore: eventStore)
        event.title = "💳 \(card.name) Ödeme Günü"

        let gregorian = Calendar(identifier: .gregorian)
        var components = gregorian.dateComponents([.year, .month, .day], from: dueDate)
        components.timeZone = TimeZone(identifier: "Europe/Istanbul")

        components.hour = 9
        components.minute = 0
        guard let startDate = gregorian.date(from: components) else {
            print("Başlangıç tarihi oluşturulamadı.")
            return
        }

        components.hour = 12
        components.minute = 0
        guard let endDate = gregorian.date(from: components) else {
            print("Bitiş tarihi oluşturulamadı.")
            return
        }

        event.startDate = startDate
        event.endDate = endDate
        event.notes = "Bu kartın son ödeme tarihi: \(formatted(date: dueDate))\n\(identifierTag)"
        event.calendar = eventCalendar
        event.url = URL(string: "cardapp://card/\(card.id.uuidString)")

        do {
            try eventStore.save(event, span: .thisEvent)
            print("Yeni etkinlik eklendi: \(event.title ?? "")")
        } catch {
            print("Etkinlik eklenemedi: \(error.localizedDescription)")
        }
    }


    func removeEvent(for card: CreditCard) {
        guard let calendar = calendar else { return }

        let identifierTag = "CARD-ID: \(card.id.uuidString)"
        let predicate = eventStore.predicateForEvents(
            withStart: Date().addingTimeInterval(-60*60*24*365),
            end: Date().addingTimeInterval(60*60*24*365),
            calendars: [calendar]
        )
        
        let events = eventStore.events(matching: predicate)
        for event in events where event.notes?.contains(identifierTag) == true {
            do {
                try eventStore.remove(event, span: .thisEvent)
                print("Takvimden silindi: \(event.title ?? "")")
            } catch {
                print("Etkinlik silinemedi: \(error.localizedDescription)")
            }
        }
    }

    func cleanUpPastEvents() {
        guard let calendar = calendar else { return }

        let now = Date()
        let predicate = eventStore.predicateForEvents(
            withStart: Date.distantPast,
            end: now,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)
        for event in events {
            do {
                try eventStore.remove(event, span: .thisEvent)
                print("Geçmiş etkinlik silindi: \(event.title ?? "")")
            } catch {
                print("Geçmiş etkinlik silinemedi: \(error.localizedDescription)")
            }
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: date)
    }
}
