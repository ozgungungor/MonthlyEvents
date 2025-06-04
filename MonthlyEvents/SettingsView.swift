import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale // Mevcut locale'i almak için

    // AppStorage'dan dil tercihini okuma ve yazma
    // Uygulamanızın App struct'ında varsayılan dil ayarlanmış olmalı
    @AppStorage("appLanguage") var currentLanguage: String = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"

    // Geçici olarak değişiklikleri tutacak @State değişkenleri
    @State private var tempIsMondayHoliday: Bool
    @State private var tempIsTuesdayHoliday: Bool
    @State private var tempIsWednesdayHoliday: Bool
    @State private var tempIsThursdayHoliday: Bool
    @State private var tempIsFridayHoliday: Bool
    @State private var tempIsSaturdayHoliday: Bool
    @State private var tempIsSundayHoliday: Bool
    @State private var tempCustomHolidayKeywords: String
    @State private var tempSelectedLanguage: String // Dil seçimi için geçici state

    // AppStorage'dan okunan gerçek değerler
    @AppStorage("isMondayHoliday") private var isMondayHoliday: Bool = false
    @AppStorage("isTuesdayHoliday") private var isTuesdayHoliday: Bool = false
    @AppStorage("isWednesdayHoliday") private var isWednesdayHoliday: Bool = false
    @AppStorage("isThursdayHoliday") private var isThursdayHoliday: Bool = false
    @AppStorage("isFridayHoliday") private var isFridayHoliday: Bool = false
    @AppStorage("isSaturdayHoliday") private var isSaturdayHoliday: Bool = true
    @AppStorage("isSundayHoliday") private var isSundayHoliday: Bool = true
    @AppStorage("customHolidayKeywords") private var customHolidayKeywords: String = "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival"

    // Desteklenen diller
    let supportedLanguages = [
        Language(code: "en", nameKey: "ENGLISH"),
        Language(code: "tr", nameKey: "TURKISH")
    ]

    struct Language: Identifiable, Hashable {
        let id = UUID()
        let code: String
        let nameKey: String // Localizable.strings için anahtar
    }

    init() {
        // @AppStorage'daki mevcut değerleri @State değişkenlerine kopyala
        _tempIsMondayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isMondayHoliday"))
        _tempIsTuesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isTuesdayHoliday"))
        _tempIsWednesdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isWednesdayHoliday"))
        _tempIsThursdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isThursdayHoliday"))
        _tempIsFridayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isFridayHoliday"))
        _tempIsSaturdayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isSaturdayHoliday"))
        _tempIsSundayHoliday = State(initialValue: UserDefaults.standard.bool(forKey: "isSundayHoliday"))
        _tempCustomHolidayKeywords = State(initialValue: UserDefaults.standard.string(forKey: "customHolidayKeywords") ?? "bayram,tatil,resmi tatil,yılbaşı,ramazan,kurban,arefe,cumhuriyet,atatürk,zafer,çocuk,gençlik,spor,egemenlik,işçi,demokrasi,milli birlik,holiday,vacation,eid,festival")
        // Başlangıçta seçili dili ayarla
        _tempSelectedLanguage = State(initialValue: UserDefaults.standard.string(forKey: "appLanguage") ?? Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en")
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("LANGUAGE_SETTINGS_SECTION_HEADER")) {
                    Picker(selection: $tempSelectedLanguage, label: Text("SELECT_LANGUAGE_PICKER_LABEL")) {
                        ForEach(supportedLanguages, id: \.code) { lang in
                            Text(LocalizedStringKey(lang.nameKey)).tag(lang.code)
                        }
                    }
                    .onChange(of: tempSelectedLanguage) { newValue in
                        // Kullanıcı dili değiştirdiğinde hemen AppStorage'a yazılır.
                        // Bu, App struct'ının locale'i güncellemesini tetikler.
                         print("Dil değişti: \(newValue)")
                    }
                }

                Section(header: Text("WEEKLY_HOLIDAYS_SECTION_HEADER")) {
                    Toggle(LocalizedStringKey("MONDAY"), isOn: $tempIsMondayHoliday)
                    Toggle(LocalizedStringKey("TUESDAY"), isOn: $tempIsTuesdayHoliday)
                    Toggle(LocalizedStringKey("WEDNESDAY"), isOn: $tempIsWednesdayHoliday)
                    Toggle(LocalizedStringKey("THURSDAY"), isOn: $tempIsThursdayHoliday)
                    Toggle(LocalizedStringKey("FRIDAY"), isOn: $tempIsFridayHoliday)
                    Toggle(LocalizedStringKey("SATURDAY"), isOn: $tempIsSaturdayHoliday)
                    Toggle(LocalizedStringKey("SUNDAY"), isOn: $tempIsSundayHoliday)
                }

                Section(header: Text("CALENDAR_HOLIDAY_KEYWORDS_SECTION_HEADER")) {
                    TextEditor(text: $tempCustomHolidayKeywords)
                        .frame(minHeight: 100)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("KEYWORDS_PROMPT")
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
                        // Dil ayarını kaydet
                        currentLanguage = tempSelectedLanguage
                        
                        // Diğer ayarları kaydet
                        isMondayHoliday = tempIsMondayHoliday
                        isTuesdayHoliday = tempIsTuesdayHoliday
                        isWednesdayHoliday = tempIsWednesdayHoliday
                        isThursdayHoliday = tempIsThursdayHoliday
                        isFridayHoliday = tempIsFridayHoliday
                        isSaturdayHoliday = tempIsSaturdayHoliday
                        isSundayHoliday = tempIsSundayHoliday
                        customHolidayKeywords = tempCustomHolidayKeywords
                        
                        // Ayarlar kaydedildikten sonra, uygulamanın yeniden yüklenmesi gerekebilir
                        // veya ana görünümün güncellenmesi için bir mekanizma tetiklenebilir.
                        // .environment(\.locale, Locale(identifier: currentLanguage)) değişikliği
                        // App struct seviyesinde yapıldığı için SwiftUI bunu otomatik yönetmeli.
                        dismiss()
                    }
                }
            }
            // View ilk göründüğünde tempSelectedLanguage'ı currentLanguage ile senkronize et
            .onAppear {
                tempSelectedLanguage = currentLanguage
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
