import Foundation
import CloudKit

class CloudKitManager {
    
    static let shared = CloudKitManager()
    private let privateDatabase = CKContainer.default().privateCloudDatabase
    
    // MARK: - Record Types & IDs
    private let cardRecordType = "CreditCardEntity"
    private let settingsRecordType = "UserSettings"
    private var settingsRecordID: CKRecord.ID {
        CKRecord.ID(recordName: "sharedUserSettings") // Tüm ayarlar için tek ve sabit bir ID
    }

    private init() {}
    
    // MARK: - Card Management
    
    func save(card: CreditCard) {
        let record = createCardRecord(from: card)
        saveCardRecord(record)
    }

    func update(card: CreditCard) {
        let record = createCardRecord(from: card)
        saveCardRecord(record)
    }
    
    func delete(cardID: UUID, completion: @escaping (Bool) -> Void) {
        let recordID = CKRecord.ID(recordName: cardID.uuidString)
        privateDatabase.delete(withRecordID: recordID) { (deletedRecordID, error) in
            if let error = error {
                print("HATA: CloudKit kart kaydı silinemedi: \(error)")
                completion(false)
                return
            }
            print("BAŞARILI: CloudKit'ten kart silindi: \(deletedRecordID?.recordName ?? "Bilinmiyor")")
            completion(true)
        }
    }

    func fetchCards() async -> [CreditCard] {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: cardRecordType, predicate: predicate)
        
        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query)
            let cards = matchResults.compactMap { (_, result) -> CreditCard? in
                if case .success(let record) = result, let data = record["encodedData"] as? Data {
                    return try? JSONDecoder().decode(CreditCard.self, from: data)
                }
                return nil
            }
            print("BAŞARILI: CloudKit'ten \(cards.count) adet kart getirildi.")
            return cards
        } catch {
            print("HATA: CloudKit kart sorgusu başarısız oldu: \(error)")
            return []
        }
    }
    
    func hasRecords() async -> Bool {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: cardRecordType, predicate: predicate)
        do {
            let (matchResults, _) = try await privateDatabase.records(matching: query, resultsLimit: 1)
            return !matchResults.isEmpty
        } catch {
            return true
        }
    }
    
    private func saveCardRecord(_ record: CKRecord, retries: Int = 3) {
        privateDatabase.save(record) { [weak self] (savedRecord, error) in
            if let error = error as? CKError, error.code == .serverRecordChanged, retries > 0 {
                print("Kart verisi çakışması tespit edildi. Çözümleniyor...")
                guard let clientRecord = error.clientRecord, let serverRecord = error.serverRecord else { return }
                let mergedRecord = self?.resolveConflict(client: clientRecord, server: serverRecord) ?? serverRecord
                self?.saveCardRecord(mergedRecord, retries: retries - 1)
            } else if let error = error {
                print("HATA: Başka bir CloudKit kart hatası oluştu: \(error)")
            } else if let savedRecord = savedRecord {
                print("BAŞARILI: CloudKit kart kaydı başarıyla kaydedildi/güncellendi: \(savedRecord.recordID.recordName)")
            }
        }
    }
    
    // MARK: - Settings Management (YENİ EKLENEN BÖLÜM)

    /// Ayarları CloudKit'ten çeker.
    /// - Parameter completion: Sonuç olarak bir ayar sözlüğü veya nil döner.
    func fetchSettings(completion: @escaping ([String: Any]?) -> Void) {
        privateDatabase.fetch(withRecordID: settingsRecordID) { (record, error) in
            if let record = record {
                // Kayıt bulundu, sözlüğe dönüştür
                var settings: [String: Any] = [:]
                settings["appLanguage"] = record["appLanguage"] as? String ?? "en"
                settings["isMondayHoliday"] = (record["isMondayHoliday"] as? Int == 1)
                settings["isTuesdayHoliday"] = (record["isTuesdayHoliday"] as? Int == 1)
                settings["isWednesdayHoliday"] = (record["isWednesdayHoliday"] as? Int == 1)
                settings["isThursdayHoliday"] = (record["isThursdayHoliday"] as? Int == 1)
                settings["isFridayHoliday"] = (record["isFridayHoliday"] as? Int == 1)
                settings["isSaturdayHoliday"] = (record["isSaturdayHoliday"] as? Int == 1)
                settings["isSundayHoliday"] = (record["isSundayHoliday"] as? Int == 1)
                settings["customHolidayKeywords"] = record["customHolidayKeywords"] as? String ?? ""
                print("Ayarlar CloudKit'ten başarıyla çekildi.")
                completion(settings)
            } else if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Kayıt bulunamadı (ilk açılış), nil dönerek varsayılan ayarların kullanılmasını sağla.
                print("CloudKit'te ayar kaydı bulunamadı. Varsayılanlar kullanılacak.")
                completion(nil)
            } else {
                print("HATA: CloudKit'ten ayarlar çekilemedi: \(error?.localizedDescription ?? "Bilinmeyen Hata")")
                completion(nil)
            }
        }
    }

    /// Verilen ayar sözlüğünü CloudKit'e kaydeder.
    /// - Parameter settings: Kaydedilecek ayarları içeren sözlük.
    func saveSettings(settings: [String: Any]) {
        privateDatabase.fetch(withRecordID: settingsRecordID) { [weak self] (record, error) in
            guard let self = self else { return }
            let recordToSave = record ?? CKRecord(recordType: self.settingsRecordType, recordID: self.settingsRecordID)

            for (key, value) in settings {
                if let boolValue = value as? Bool {
                    recordToSave[key] = (boolValue ? 1 : 0) as CKRecordValue
                } else if let stringValue = value as? String {
                    recordToSave[key] = stringValue as CKRecordValue
                }
            }
            
            self.privateDatabase.save(recordToSave) { (savedRecord, error) in
                if let error = error {
                    print("HATA: Ayarlar CloudKit'e kaydedilemedi: \(error)")
                } else {
                    print("BAŞARILI: Ayarlar CloudKit'e kaydedildi.")
                }
            }
        }
    }

    // MARK: - Private Helpers
    
    private func resolveConflict(client: CKRecord, server: CKRecord) -> CKRecord {
        let mergedRecord = server
        let clientKeys = client.allKeys()
        for key in clientKeys {
            mergedRecord[key] = client[key]
        }
        print("Birleştirme tamamlandı. İstemci değişiklikleri sunucu kaydına uygulandı.")
        return mergedRecord
    }
    
    private func createCardRecord(from card: CreditCard) -> CKRecord {
        let record = CKRecord(recordType: cardRecordType, recordID: CKRecord.ID(recordName: card.id.uuidString))
        do {
            let data = try JSONEncoder().encode(card)
            record["encodedData"] = data as CKRecordValue
        } catch {
            print("HATA: CloudKit için CreditCard kodlanamadı: \(error)")
        }
        return record
    }
}
