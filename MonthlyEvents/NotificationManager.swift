import UserNotifications
import SwiftUI // Make sure SwiftUI is imported for LocalizedStringKey
import os.log

class NotificationManager: NSObject, UNUserNotificationCenterDelegate, ObservableObject {
    static let shared = NotificationManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationManager")

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("Bildirim izni verildi.")
            } else {
                logger.warning("Bildirim izni reddedildi.")
            }
            return granted
        } catch {
            logger.error("Bildirim izni isteği başarısız oldu: \(error.localizedDescription)")
            return false
        }
    }

    func scheduleReminders(for card: CreditCard, dueDates: [Date], locale: Locale) {
        // Kart aktif değilse veya taksitleri bitmişse bildirim planlama
        guard card.isActive, (card.type != .loan || (card.remainingInstallments ?? 1) > 0) else {
            removeAllScheduledNotifications(for: card.id)
            return
        }

        removeAllScheduledNotifications(for: card.id) // Mevcut bildirimleri temizle

        let content = UNMutableNotificationContent()
        content.sound = .defaultCritical
        content.userInfo = ["cardID": card.id.uuidString]

        for (index, date) in dueDates.enumerated() {
            // Sadece yakın gelecekteki tarihler için bildirim planla
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day], from: date)

            // GÜNCELLENDİ: Abonelik türü için başlık ekle
            switch card.type {
            case .card:
                content.title = String(format: localizedString(forKey: "NOTIFICATION_TITLE_CARD", locale: locale), card.name)
                // Düzeltme: `NOTIFICATION_BODY_CARD` "%@ kartınızın (**** %@) son ödeme günü yaklaşıyor!" şeklinde iki string bekliyordu.
                // İkinci `%@` için `card.lastFourDigits` kullanılacak, `card.dueDate` değil.
                // Eğer `card.dueDate` isteniyorsa format "%@ kartınızın (**** %d) son ödeme günü yaklaşıyor!" olmalıydı.
                // Mevcut Localizable.strings'deki formatı koruyarak `card.lastFourDigits` kullanıldı.
                content.body = String(format: localizedString(forKey: "NOTIFICATION_BODY_CARD", locale: locale), card.name, card.lastFourDigits)
            case .loan:
                if let total = card.totalInstallments, let remaining = card.remainingInstallments {
                    let paymentsMade = total - remaining
                    let currentInstallment = paymentsMade + 1 + index
                    content.title = String(format: localizedString(forKey: "NOTIFICATION_TITLE_LOAN", locale: locale), card.name)
                    // Düzeltme: `NOTIFICATION_BODY_LOAN` "%d/%d" şeklinde iki Int bekliyor.
                    content.body = String(format: localizedString(forKey: "NOTIFICATION_BODY_LOAN", locale: locale), currentInstallment, total)
                } else {
                    // Bu senaryoda `NOTIFICATION_BODY_LOAN_SIMPLE` anahtarı Localizable.strings'inizde yok.
                    // Bu yüzden ya eklemelisiniz ya da farklı bir mesaj kullanmalısınız.
                    // Geçici olarak genel bir format kullanıldı.
                    content.title = String(format: localizedString(forKey: "NOTIFICATION_TITLE_LOAN", locale: locale), card.name)
                    content.body = localizedString(forKey: "NOTIFICATION_BODY_GENERAL", locale: locale).replacingOccurrences(of: "%@", with: card.name) // Veya uygun bir anahtar oluşturun
                }
            case .oneTimePayment:
                content.title = String(format: localizedString(forKey: "NOTIFICATION_TITLE_ONETIME", locale: locale), card.name)
                // Düzeltme: `NOTIFICATION_BODY_ONETIME` anahtarı Localizable.strings'inizde yok.
                // Geçici olarak genel bir format kullanıldı.
                content.body = localizedString(forKey: "NOTIFICATION_BODY_GENERAL", locale: locale).replacingOccurrences(of: "%@", with: card.name) // Veya uygun bir anahtar oluşturun
            case .subscription:
                content.title = String(format: localizedString(forKey: "NOTIFICATION_TITLE_SUBSCRIPTION", locale: locale), card.name)
                if card.billingCycle == .annually, let month = card.annualBillingMonth {
                    // Düzeltme: `NOTIFICATION_BODY_SUBSCRIPTION_ANNUAL` anahtarı Localizable.strings'inizde yok.
                    // `SUBSCRIPTION_ANNUAL_STATUS` Localizable.strings'de var, onu kullanabiliriz.
                    // Ancak bildirim içeriği için daha spesifik bir anahtar daha iyi olur.
                    // Geçici olarak, format specifier uyumsuzluğunu gidermek için düz metin veya uygun bir format.
                    content.body = String(format: localizedString(forKey: "NOTIFICATION_BODY_SUBSCRIPTION_ANNUAL", locale: locale), card.name, localizedMonthName(month: month, locale: locale))
                } else {
                    // Düzeltme: `NOTIFICATION_BODY_SUBSCRIPTION_MONTHLY` anahtarı Localizable.strings'inizde yok.
                    // `NOTIFICATION_BODY_SUBSCRIPTION` anahtarı Localizable.strings'de var ve tek bir `%@` bekliyor.
                    content.body = String(format: localizedString(forKey: "NOTIFICATION_BODY_SUBSCRIPTION", locale: locale), card.name)
                }
            }

            guard let year = components.year, let month = components.month, let day = components.day else {
                logger.error("Bildirim tarih bileşenleri eksik veya geçersiz.")
                continue
            }

            var triggerComponents = DateComponents()
            triggerComponents.year = year
            triggerComponents.month = month
            triggerComponents.day = day
            // Opsiyonel: Bildirimin gün içinde belirli bir saatte gelmesini isterseniz
            triggerComponents.hour = 9 // Sabah 9
            triggerComponents.minute = 0 // 0 dakika

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let requestIdentifier = "paymentReminder-\(card.id.uuidString)-\(index)"
            let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    self.logger.error("Bildirim planlama hatası: \(error.localizedDescription)")
                } else {
                    self.logger.info("Bildirim planlandı: \(requestIdentifier) for \(card.name) on \(date)")
                }
            }
        }
        updateAppBadgeCount()
    }

    func removeAllScheduledNotifications(for cardID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["paymentReminder-\(cardID.uuidString)-0", "paymentReminder-\(cardID.uuidString)-1"])
        logger.info("Planlanmış bildirimler kaldırıldı: \(cardID.uuidString)")
        updateAppBadgeCount()
    }

    func removeAllScheduledNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        logger.info("Tüm bekleyen bildirimler kaldırıldı.")
        updateAppBadgeCount()
    }

    func updateAppBadgeCount() {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = notifications.count
                self.logger.info("Uygulama bildirim rozeti güncellendi: \(notifications.count)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    private func localizedString(forKey key: String, locale: Locale) -> String {
        // Güvenli unwrapping için languageCode kullanın.
        // Locale.languageCode?.identifier yerine, daha güvenli bir opsiyonel zincirleme veya nil-coalescing.
        let languageIdentifier = locale.language.languageCode?.identifier ?? "en" // Varsayılan "en"
        if let path = Bundle.main.path(forResource: languageIdentifier, ofType: "lproj"),
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
