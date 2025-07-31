import SwiftUI

@main
struct MonthlyEventsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // AppStorage'dan dil tercihini okuma
    // Varsayılan olarak cihazın tercih ettiği dili veya İngilizce'yi kullanır
    @AppStorage("appLanguage") var currentLanguage: String = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.locale, Locale(identifier: currentLanguage)) // Seçilen dili environment'a ekle
        }
    }
}
