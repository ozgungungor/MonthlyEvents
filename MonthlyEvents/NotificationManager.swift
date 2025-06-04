import UserNotifications
import Foundation // UUID için

// Sorumluluk: Bildirimleri yönetir.
class NotificationManager {
    static let shared = NotificationManager()
    private init() {} // Singleton
    
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Bildirim izni isteği başarısız: \(error)")
            return false
        }
    }
    
    func scheduleReminder(for card: CreditCard, dueDate: Date, idSuffix: String? = nil) {
        let center = UNUserNotificationCenter.current()
        let baseIdentifier = card.id.uuidString
        let identifier = idSuffix == nil ? baseIdentifier : "\(baseIdentifier)-\(idSuffix!)"
        
        // Önceki aynı ID'li bildirimi temizle
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        guard card.isActive else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "💳 Kredi Kartı Hatırlatması"
        content.body = "\(card.name) kartınızın son ödeme günü yaklaştı! (**** \(card.lastFourDigits))"
        content.sound = .default
        content.badge = 1
        
        var notificationComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
        notificationComponents.hour = 9
        notificationComponents.minute = 0
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: notificationComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        center.add(request) { error in
            if let error = error {
                print("Bildirim eklenirken hata: \(error.localizedDescription)")
            } else {
                print("\(card.name) için bildirim \(dueDate) tarihine kuruldu. ID: \(identifier)")
            }
        }
    }

    func cancelReminder(for card: CreditCard) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [card.id.uuidString])
    }

    func removeReminders(for card: CreditCard) {
        let ids = [
            card.id.uuidString,
            "\(card.id.uuidString)-thisMonth",
            "\(card.id.uuidString)-nextMonth"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
