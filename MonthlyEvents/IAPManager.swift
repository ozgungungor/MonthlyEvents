import Foundation
import StoreKit
import SwiftUI // @AppStorage için

class IAPManager: NSObject, ObservableObject {
    static let shared = IAPManager()

    @Published var products: [SKProduct] = []
    @Published var transactionState: SKPaymentTransactionState?

    // Reklam kaldırma durumu için @AppStorage
    @AppStorage("areAdsRemoved") var areAdsRemoved: Bool = false

    private var productRequest: SKProductsRequest?

    // Ürün tanımlayıcıları (App Store Connect'teki aynı)
    private let removeAdsProductID = "com.ozgungungor.paynify.removeads"
    private let supportSmallProductID = "com.ozgungungor.paynify.support.small"
    private let supportMediumProductID = "com.ozgungungor.paynify.support.medium"
    private let supportLargeProductID = "com.ozgungungor.paynify.support.large"

    override init() {
        super.init()
        // SKPaymentTransactionObserver'ı ekliyoruz ki satın alma güncellemelerini takip edebilelim
        SKPaymentQueue.default().add(self)
        fetchProducts()
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    func fetchProducts() {
        let productIDs: Set<String> = [
            removeAdsProductID,
            supportSmallProductID,
            supportMediumProductID,
            supportLargeProductID
        ]

        productRequest = SKProductsRequest(productIdentifiers: productIDs)
        productRequest?.delegate = self
        productRequest?.start()
    }

    func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }

    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    // Reklamların gösterilip gösterilmeyeceğini belirleyen yardımcı fonksiyon
    func shouldShowAds() -> Bool {
        return !areAdsRemoved
    }
}

// MARK: - SKProductsRequestDelegate
extension IAPManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        DispatchQueue.main.async {
            self.products = response.products
            print("Ürünler başarıyla yüklendi: \(self.products.map { $0.productIdentifier })")
            for invalidIdentifier in response.invalidProductIdentifiers {
                print("Geçersiz Ürün Tanımlayıcı: \(invalidIdentifier)")
            }
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Ürün isteği başarısız oldu: \(error.localizedDescription)")
    }
}

// MARK: - SKPaymentTransactionObserver
extension IAPManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchasing:
                transactionState = .purchasing
                print("Satın alma işlemi sürüyor...")
            case .purchased:
                transactionState = .purchased
                handlePurchase(transaction: transaction)
                SKPaymentQueue.default().finishTransaction(transaction)
                print("Satın alma başarılı: \(transaction.payment.productIdentifier)")
            case .restored:
                transactionState = .restored
                handlePurchase(transaction: transaction) // Geri yükleme de satın alma gibi işlenir
                SKPaymentQueue.default().finishTransaction(transaction)
                print("Geri yükleme başarılı: \(transaction.payment.productIdentifier)")
            case .failed:
                transactionState = .failed
                if let error = transaction.error as? SKError {
                    if error.code != .paymentCancelled {
                        print("Satın alma başarısız: \(error.localizedDescription)")
                    } else {
                        print("Satın alma iptal edildi.")
                    }
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            case .deferred:
                transactionState = .deferred
                print("Satın alma beklemede (onay bekleniyor)...")
            @unknown default:
                break
            }
        }
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        print("Tüm geri yüklemeler tamamlandı.")
        if queue.transactions.isEmpty && products.isEmpty {
            // Eğer hiç restore edilecek bir şey yoksa ve ürünler bile yüklenmemişse bir mesaj gösterebiliriz
            print("Geri yüklenecek bir satın alma bulunamadı.")
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("Geri yükleme başarısız oldu: \(error.localizedDescription)")
    }

    private func handlePurchase(transaction: SKPaymentTransaction) {
        switch transaction.payment.productIdentifier {
        case removeAdsProductID:
            areAdsRemoved = true
            print("Reklamlar kaldırıldı!")
            // Reklamları hemen gizlemek için BannerView'i yenileme mekanizması tetiklenebilir
            // Örneğin, bir NotificationCenter yayını veya bir @AppStorage değeri değişikliği
        case supportSmallProductID, supportMediumProductID, supportLargeProductID:
            print("Destek satın alımı başarılı: \(transaction.payment.productIdentifier)")
            // Tüketilebilir ürün olduğu için burada bir teşekkür mesajı gösterilebilir veya uygulama içi ödül verilebilir
        default:
            break
        }
    }
}
