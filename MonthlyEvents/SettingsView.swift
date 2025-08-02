import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    // State'ler
    @StateObject private var holidayService = HolidayService.shared
    @State private var availableCalendars: [EKCalendar] = []
    @State private var tempSelectedCalendarIDs: Set<String>
    @State private var tempSelectedLanguage: String
    @State private var tempIsMondayHoliday: Bool
    @State private var tempIsTuesdayHoliday: Bool
    @State private var tempIsWednesdayHoliday: Bool
    @State private var tempIsThursdayHoliday: Bool
    @State private var tempIsFridayHoliday: Bool
    @State private var tempIsSaturdayHoliday: Bool
    @State private var tempIsSundayHoliday: Bool
    @State private var tempCustomHolidayKeywords: String

    let supportedLanguages = [
        Language(code: "en", nameKey: "ENGLISH"),
        Language(code: "tr", nameKey: "TURKISH")
    ]

    struct Language: Identifiable, Hashable {
        let id = UUID()
        let code: String
        let nameKey: String
    }

    init() {
        // State değişkenlerini UserDefaults'taki son değerlerle doldur
        _tempSelectedLanguage = State(initialValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en")
        _tempIsMondayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isMondayHoliday"))
        _tempIsTuesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isTuesdayHoliday"))
        _tempIsWednesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isWednesdayHoliday"))
        _tempIsThursdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isThursdayHoliday"))
        _tempIsFridayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isFridayHoliday"))
        _tempIsSaturdayHoliday = State(initialValue: UserDefaults.standard.object(forKey: "isSaturdayHoliday") as? Bool ?? true)
        _tempIsSundayHoliday = State(initialValue: UserDefaults.standard.object(forKey: "isSundayHoliday") as? Bool ?? true)
        _tempCustomHolidayKeywords = State(initialValue: UserDefaults.standard.string(forKey: "customHolidayKeywords") ?? "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival")
        _tempSelectedCalendarIDs = State(initialValue: Set(HolidayService.shared.loadSelectedCalendarIDs()))
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(LocalizedStringKey("LANGUAGE_SETTINGS_SECTION_HEADER"))) {
                    Picker(selection: $tempSelectedLanguage, label: Text(LocalizedStringKey("SELECT_LANGUAGE_PICKER_LABEL"))) {
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(LocalizedStringKey(lang.nameKey)).tag(lang.code)
                        }
                    }
                }
                
                if holidayService.hasCalendarAccess {
                    Section(header: Text(LocalizedStringKey("CALENDAR_SELECTION_SECTION_HEADER"))) {
                        ForEach(availableCalendars, id: \.calendarIdentifier) { calendar in
                            Button(action: {
                                toggleCalendarSelection(for: calendar.calendarIdentifier)
                            }) {
                                HStack {
                                    Image(systemName: tempSelectedCalendarIDs.contains(calendar.calendarIdentifier) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(Color(cgColor: calendar.cgColor))
                                    Text(calendar.title)
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }

                Section(header: Text(LocalizedStringKey("WEEKLY_HOLIDAYS_SECTION_HEADER"))) {
                    Toggle(LocalizedStringKey("MONDAY"), isOn: $tempIsMondayHoliday)
                    Toggle(LocalizedStringKey("TUESDAY"), isOn: $tempIsTuesdayHoliday)
                    Toggle(LocalizedStringKey("WEDNESDAY"), isOn: $tempIsWednesdayHoliday)
                    Toggle(LocalizedStringKey("THURSDAY"), isOn: $tempIsThursdayHoliday)
                    Toggle(LocalizedStringKey("FRIDAY"), isOn: $tempIsFridayHoliday)
                    Toggle(LocalizedStringKey("SATURDAY"), isOn: $tempIsSaturdayHoliday)
                    Toggle(LocalizedStringKey("SUNDAY"), isOn: $tempIsSundayHoliday)
                }

                Section(header: Text(LocalizedStringKey("CALENDAR_HOLIDAY_KEYWORDS_SECTION_HEADER"))) {
                    TextEditor(text: $tempCustomHolidayKeywords)
                        .frame(minHeight: 100)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text(LocalizedStringKey("KEYWORDS_PROMPT"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(LocalizedStringKey("SETTINGS_TITLE"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedStringKey("CANCEL")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedStringKey("SAVE")) {
                        saveSettings()
                        dismiss()
                    }
                }
            }
            .onAppear {
                fetchSettingsFromCloudKit()
                self.availableCalendars = holidayService.getAvailableCalendars()
            }
        }
    }
    
    private func toggleCalendarSelection(for id: String) {
        if tempSelectedCalendarIDs.contains(id) {
            tempSelectedCalendarIDs.remove(id)
        } else {
            tempSelectedCalendarIDs.insert(id)
        }
    }
    
    /// Ayarları CloudKit'ten çeker ve UI'ı günceller.
    private func fetchSettingsFromCloudKit() {
        CloudKitManager.shared.fetchSettings { fetchedSettings in
            guard let settings = fetchedSettings else { return }
            
            DispatchQueue.main.async {
                self.tempSelectedLanguage = settings["appLanguage"] as? String ?? self.tempSelectedLanguage
                self.tempIsMondayHoliday = settings["isMondayHoliday"] as? Bool ?? self.tempIsMondayHoliday
                self.tempIsTuesdayHoliday = settings["isTuesdayHoliday"] as? Bool ?? self.tempIsTuesdayHoliday
                self.tempIsWednesdayHoliday = settings["isWednesdayHoliday"] as? Bool ?? self.tempIsWednesdayHoliday
                self.tempIsThursdayHoliday = settings["isThursdayHoliday"] as? Bool ?? self.tempIsThursdayHoliday
                self.tempIsFridayHoliday = settings["isFridayHoliday"] as? Bool ?? self.tempIsFridayHoliday
                self.tempIsSaturdayHoliday = settings["isSaturdayHoliday"] as? Bool ?? self.tempIsSaturdayHoliday
                self.tempIsSundayHoliday = settings["isSundayHoliday"] as? Bool ?? self.tempIsSundayHoliday
                self.tempCustomHolidayKeywords = settings["customHolidayKeywords"] as? String ?? self.tempCustomHolidayKeywords
                
                // --- YENİ EKLENEN KOD (FETCH) ---
                // CloudKit'ten gelen takvim seçimi verisini işle
                if let fetchedIDsJSON = settings["selectedCalendarIDsJSON"] as? String {
                    // Önce yerel @AppStorage'ı güncelle
                    UserDefaults.standard.set(fetchedIDsJSON, forKey: "selectedCalendarIDsJSON")
                    
                    // Sonra UI'daki @State'i güncelle
                    if let data = fetchedIDsJSON.data(using: .utf8),
                       let ids = try? JSONDecoder().decode([String].self, from: data) {
                        self.tempSelectedCalendarIDs = Set(ids)
                    }
                }
            }
        }
    }
    
    /// Ayarları hem yerel olarak (UserDefaults) hem de buluta (CloudKit) kaydeder.
    private func saveSettings() {
        // 1. Seçili takvimleri HolidayService üzerinden yerel olarak kaydet
        holidayService.saveSelectedCalendarIDs(Array(tempSelectedCalendarIDs))
        
        // 2. Diğer ayarları yerel UserDefaults'a kaydet
        UserDefaults.standard.set(tempSelectedLanguage, forKey: "appLanguage")
        // ... (diğer UserDefaults set işlemleri) ...
        UserDefaults.standard.set(tempIsSaturdayHoliday, forKey: "isSaturdayHoliday")
        UserDefaults.standard.set(tempIsSundayHoliday, forKey: "isSundayHoliday")
        UserDefaults.standard.set(tempCustomHolidayKeywords, forKey: "customHolidayKeywords")
        
        // 3. CloudKit'e kaydetmek için bir sözlük oluştur
        var settingsDict: [String: Any] = [:]
        settingsDict["appLanguage"] = tempSelectedLanguage
        settingsDict["isMondayHoliday"] = tempIsMondayHoliday
        settingsDict["isTuesdayHoliday"] = tempIsTuesdayHoliday
        settingsDict["isWednesdayHoliday"] = tempIsWednesdayHoliday
        settingsDict["isThursdayHoliday"] = tempIsThursdayHoliday
        settingsDict["isFridayHoliday"] = tempIsFridayHoliday
        settingsDict["isSaturdayHoliday"] = tempIsSaturdayHoliday
        settingsDict["isSundayHoliday"] = tempIsSundayHoliday
        settingsDict["customHolidayKeywords"] = tempCustomHolidayKeywords
        
        // --- YENİ EKLENEN KOD (SAVE) ---
        // Takvim seçimini de CloudKit'e gönderilecek sözlüğe ekle
        settingsDict["selectedCalendarIDsJSON"] = UserDefaults.standard.string(forKey: "selectedCalendarIDsJSON") ?? ""

        // 4. CloudKitManager aracılığıyla buluta kaydet
        CloudKitManager.shared.saveSettings(settings: settingsDict)
        
        // 5. Diğer servisleri güncellenmiş ayarlarla yeniden yapılandır
        holidayService.refresh()
        CardDataManager.shared.rescheduleAllEventsAndNotifications()
    }
}

// Preview için yardımcı
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
