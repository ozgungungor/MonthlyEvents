import SwiftUI
import GoogleMobileAds

@main
struct PaynifyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage("appLanguage") var currentLanguage: String = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

    init() {
        // HATA DÜZELTMESİ: 'shared()' bir fonksiyon değil, bir özelliktir.
        // Bu yüzden 'MobileAds.shared' olarak parantezsiz kullanılmalıdır.
        MobileAds.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            // MainView ve BannerView'i bir VStack içine alarak dikey olarak düzenliyoruz.
            // Bu, BannerView'in her zaman en altta kalmasını sağlar.
            VStack(spacing: 0) { // spacing: 0, MainView ile BannerView arasında boşluk olmamasını sağlar
                MainView()
                    .environment(\.locale, Locale(identifier: currentLanguage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity) // MainView'in tüm kullanılabilir alanı kaplamasını sağlar

                // Banner her zaman en altta görünecek
                BannerView()
                    .frame(height: 50) // Reklamın sabit yüksekliği
                    .background(Color(.systemBackground)) // Arka planı belirginleştir
            }
            // Klavyenin banner'ı veya içeriği örtmesini engellemek için genel ignoresSafeArea
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}
