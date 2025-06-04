import UIKit
import UserNotifications
import Foundation

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        
        if let uuid = UUID(uuidString: identifier),
           let card = CardDataManager.shared.card(withId: uuid) {
            
            // Ödeme tarihleri dizisini alıyoruz
            let dueDates = DueDateCalculator.calculateDueDates(for: card, using: HolidayService.shared)
            
            // İlk ödeme tarihini güvenle alıyoruz
            guard let newDueDate = dueDates.first else {
                completionHandler()
                return
            }
            
            NotificationManager.shared.scheduleReminder(for: card, dueDate: newDueDate)
            
            // Kart ID'yi SwiftUI veya diğer modüllere bildiriyoruz
            NotificationCenter.default.post(name: Notification.Name("OpenCard"), object: uuid.uuidString)
        }
        
        completionHandler()
    }
    
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("Uygulama URL ile açıldı: \(url)")
        
        if url.scheme == "cardapp" {
            if url.host == "card", let cardID = url.pathComponents.dropFirst().first {
                print("Kart ID geldi: \(cardID)")
                NotificationCenter.default.post(name: Notification.Name("OpenCard"), object: cardID)
                return true
            }
        }
        
        return false
    }
}
