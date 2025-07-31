import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale // Ortamdaki güncel dil bilgisini almak için kullanışlı

    @AppStorage("appLanguage") var currentLanguage: String = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

    @State private var tempIsMondayHoliday: Bool
    @State private var tempIsTuesdayHoliday: Bool
    @State private var tempIsWednesdayHoliday: Bool
    @State private var tempIsThursdayHoliday: Bool
    @State private var tempIsFridayHoliday: Bool
    @State private var tempIsSaturdayHoliday: Bool
    @State private var tempIsSundayHoliday: Bool
    @State private var tempCustomHolidayKeywords: String
    @State private var tempSelectedLanguage: String

    // Bu AppStorage'lar doğrudan UI tarafından değil, temp değişkenler aracılığıyla güncelleniyor.
    // Init bloğu ve Save butonu bu bağlantıyı kurar.
    @AppStorage("isMondayHoliday") private var isMondayHoliday: Bool = false
    @AppStorage("isTuesdayHoliday") private var isTuesdayHoliday: Bool = false
    @AppStorage("isWednesdayHoliday") private var isWednesdayHoliday: Bool = false
    @AppStorage("isThursdayHoliday") private var isThursdayHoliday: Bool = false
    @AppStorage("isFridayHoliday") private var isFridayHoliday: Bool = false
    @AppStorage("isSaturdayHoliday") private var isSaturdayHoliday: Bool = true
    @AppStorage("isSundayHoliday") private var isSundayHoliday: Bool = true
    @AppStorage("customHolidayKeywords") private var customHolidayKeywords: String = "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival"

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
        // AppStorage'dan okunan başlangıç değerlerini temp değişkenlere atama
        _tempIsMondayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isMondayHoliday"))
        _tempIsTuesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isTuesdayHoliday"))
        _tempIsWednesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isWednesdayHoliday"))
        _tempIsThursdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isThursdayHoliday"))
        _tempIsFridayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isFridayHoliday"))
        _tempIsSaturdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isSaturdayHoliday"))
        _tempIsSundayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isSundayHoliday"))
        _tempCustomHolidayKeywords = State(initialValue: UserDefaults.standard.string(forKey: "customHolidayKeywords") ?? "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival")
        _tempSelectedLanguage = State(initialValue: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en")
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
                    // Dil değiştiğinde anında applyChanges'i tetikle
                    .onChange(of: tempSelectedLanguage) { newLanguage in
                        // currentLanguage'i anında güncelleyerek MainView'daki onChange'i tetikleyebiliriz.
                        // Ancak AppStorage'ın güncellenmesi biraz zaman alabilir.
                        // En garanti yol, kaydet butonunda tüm değişiklikleri tek seferde uygulamaktır.
                        // Ancak Picker'ın görsel olarak güncellenmesi için burada bir değişiklik yapılabilir.
                        // currentLanguage = newLanguage // Eğer anında uygulansın isteniyorsa bu satır eklenebilir.
                        // Bu durumda MainView'daki onChange(of: currentLocale) devreye girer.
                        // Fakat burada sadece temp değeri güncellendiği için, save'e basınca değişmesi daha mantıklı.
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
                        // Temp değişkenlerdeki değerleri @AppStorage değişkenlerine kaydet
                        currentLanguage = tempSelectedLanguage // Dil ayarını kaydet
                        
                        isMondayHoliday = tempIsMondayHoliday
                        isTuesdayHoliday = tempIsTuesdayHoliday
                        isWednesdayHoliday = tempIsWednesdayHoliday
                        isThursdayHoliday = tempIsThursdayHoliday
                        isFridayHoliday = tempIsFridayHoliday
                        isSaturdayHoliday = tempIsSaturdayHoliday
                        isSundayHoliday = tempIsSundayHoliday
                        customHolidayKeywords = tempCustomHolidayKeywords
                        
                        // Tüm servisleri güncellemeleri için bilgilendir
                        // HolidayService'ı yenile
                        HolidayService.shared.refresh()
                        // Tüm kartlar için takvim etkinliklerini ve bildirimleri yeniden planla
                        // Bu, tatil günü ayarlarındaki değişiklikleri dikkate alacaktır.
                        CardDataManager.shared.rescheduleAllEventsAndNotifications()
                        
                        dismiss()
                    }
                }
            }
            .onAppear {
                // SettingsView açıldığında, AppStorage'daki güncel değerleri temp değişkenlere yükle
                // Bu init'te zaten yapılıyor ama onAppear'da tekrar kontrol etmek veya emin olmak isteyebilirsiniz
                // (init bir kere çağrılır, onAppear her görünüm oluştuğunda/göründüğünde)
                tempSelectedLanguage = currentLanguage // Picker'ın doğru başlangıç değerini göstermesi için
                tempIsMondayHoliday = isMondayHoliday
                tempIsTuesdayHoliday = isTuesdayHoliday
                tempIsWednesdayHoliday = isWednesdayHoliday
                tempIsThursdayHoliday = isThursdayHoliday
                tempIsFridayHoliday = isFridayHoliday
                tempIsSaturdayHoliday = isSaturdayHoliday
                tempIsSundayHoliday = isSundayHoliday
                tempCustomHolidayKeywords = customHolidayKeywords
            }
        }
    }
}

// Preview için yardımcı
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environment(\.locale, .init(identifier: "tr")) // Türkçe preview
        SettingsView()
            .environment(\.locale, .init(identifier: "en")) // İngilizce preview
    }
}
