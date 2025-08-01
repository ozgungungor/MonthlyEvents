import UIKit
import UserNotifications
import Foundation

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // BİLDİRİM TIKLANDIĞINDA ÇALIŞAN FONKSİYON
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if let cardIDString = response.notification.request.content.userInfo["cardID"] as? String,
           let cardID = UUID(uuidString: cardIDString) {
            
            NotificationCenter.default.post(name: Notification.Name("OpenCard"), object: cardIDString)
            
            let languageIdentifier = UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.current.identifier
            let locale = Locale(identifier: languageIdentifier)
            
            if let card = CardDataManager.shared.card(withId: cardID) {
                let dueDates = DueDateCalculator.calculateDueDates(for: card, using: HolidayService.shared)
                NotificationManager.shared.scheduleReminders(for: card, dueDates: dueDates, locale: locale)
            }
        }
        
        completionHandler()
    }
    
    // TAKVİMDEKİ ETKİNLİKTEN UYGULAMA AÇILDIĞINDA ÇALIŞAN FONKSİYON (GÜNCELLENDİ)
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("Uygulama URL ile açıldı: \(url)")
        
        // URL şeması "paynify" olarak güncellendi
        if url.scheme == "paynify", // <-- DEĞİŞTİ
           url.host == "open",
           url.pathComponents.count > 2,
           url.pathComponents[1] == "item",
           let cardID = url.pathComponents.last {
            
            print("Kart ID geldi: \(cardID)")
            NotificationCenter.default.post(name: Notification.Name("OpenCard"), object: cardID)
            return true
        }
        
        return false
    }
}
