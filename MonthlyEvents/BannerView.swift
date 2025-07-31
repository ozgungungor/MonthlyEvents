import SwiftUI
import GoogleMobileAds

struct BannerView: UIViewRepresentable {

    private let adUnitID = "ca-app-pub-4244659004257886/7305423108"

    func makeUIView(context: Context) -> GoogleMobileAds.BannerView {
        let bannerView = GoogleMobileAds.BannerView(adSize: adSizeFor(cgSize: CGSize(width: 320, height: 50)))

        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows
                .first?
                .rootViewController

        // YENİ: Hata ayıklama için delegate'i ayarlıyoruz.
        bannerView.delegate = context.coordinator

        bannerView.load(Request())
        return bannerView
    }

    func updateUIView(_ uiView: GoogleMobileAds.BannerView, context: Context) {
        // Güncelleme gerekmiyor.
    }

    // YENİ: AdMob olaylarını dinlemek için Coordinator sınıfı.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
          print("✅ Banner reklamı başarıyla yüklendi.")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
          print("❌ Banner reklamı yüklenemedi. Hata: \(error.localizedDescription)")
        }
    }
}
