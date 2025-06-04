import SwiftUI

struct CardFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var dataManager: CardDataManager
    @ObservedObject var holidayService: HolidayService
    @Environment(\.locale) var currentLocale // Mevcut locale'i al

    @State private var cardName: String
    @State private var lastFourDigits: String
    @State private var selectedDay: Int
    @State private var pickedColor: Color
    @State private var showingDeleteAlert = false

    let cardToEdit: CreditCard?
    private var mode: FormMode {
        cardToEdit == nil ? .add : .edit
    }

    enum FormMode {
        case add, edit
    }

    init(dataManager: CardDataManager, holidayService: HolidayService, cardToEdit: CreditCard? = nil) {
        self.dataManager = dataManager
        self.holidayService = holidayService
        self.cardToEdit = cardToEdit

        _cardName = State(initialValue: cardToEdit?.name ?? "")
        _lastFourDigits = State(initialValue: cardToEdit?.lastFourDigits ?? "")
        _selectedDay = State(initialValue: cardToEdit?.dueDate ?? 1)
        
        let initialColorString = cardToEdit?.color ?? "blue"
        _pickedColor = State(initialValue: Self.colorFromString(initialColorString))
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(LocalizedStringKey("SECTION_CARD_INFO")) {
                        TextField(LocalizedStringKey("TEXTFIELD_CARD_NAME_PLACEHOLDER"), text: $cardName)
                        if #available(iOS 17.0, *) {
                            TextField(LocalizedStringKey("TEXTFIELD_LAST_FOUR_DIGITS_PLACEHOLDER"), text: $lastFourDigits)
                                .keyboardType(.numberPad)
                                .onChange(of: lastFourDigits) { newValue, _ in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    if filtered.count > 4 {
                                        lastFourDigits = String(filtered.prefix(4))
                                    } else {
                                        lastFourDigits = filtered
                                    }
                                }
                        } else if #available(iOS 15.0, *) {
                             TextField(LocalizedStringKey("TEXTFIELD_LAST_FOUR_DIGITS_PLACEHOLDER"), text: $lastFourDigits)
                                .keyboardType(.numberPad)
                                .onChange(of: lastFourDigits) { newValue in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    if filtered.count > 4 {
                                        lastFourDigits = String(filtered.prefix(4))
                                    } else {
                                        lastFourDigits = filtered
                                    }
                                }
                        } else {
                            TextField(LocalizedStringKey("TEXTFIELD_LAST_FOUR_DIGITS_PLACEHOLDER"), text: $lastFourDigits)
                                .keyboardType(.numberPad)
                        }
                    }

                    Section(LocalizedStringKey("SECTION_ACCOUNT_CUTOFF")) {
                        Picker(LocalizedStringKey("PICKER_DAY_OF_MONTH_LABEL"), selection: $selectedDay) {
                            ForEach(1...31, id: \.self) { day in
                                // "DAY_TAG_FORMAT" anahtarı "%d. gün" veya "%d. day" gibi bir değere sahip olmalı
                                Text(String(format: NSLocalizedString("DAY_TAG_FORMAT", comment: "Picker day format"), day)).tag(day)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }

                    Section(LocalizedStringKey("SECTION_CARD_COLOR")) {
                        ColorPicker(LocalizedStringKey("COLORPICKER_SELECT_COLOR_LABEL"), selection: $pickedColor, supportsOpacity: false)
                    }

                    if mode == .edit {
                        Section {
                            Button(LocalizedStringKey("BUTTON_DELETE_CARD"), role: .destructive) {
                                showingDeleteAlert = true
                            }
                        }
                    }
                }

                HStack(spacing: 20) {
                    Button(LocalizedStringKey("CANCEL")) { // "CANCEL" anahtarı daha önce tanımlanmıştı
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.primary)

                    Button(LocalizedStringKey("SAVE")) { // "SAVE" anahtarı daha önce tanımlanmıştı
                        saveCard()
                    }
                    .disabled(cardName.isEmpty || lastFourDigits.count != 4)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background((cardName.isEmpty || lastFourDigits.count != 4) ? Color.gray.opacity(0.5) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle(mode == .add ? LocalizedStringKey("NAV_TITLE_ADD_CARD") : LocalizedStringKey("NAV_TITLE_EDIT_CARD"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(LocalizedStringKey("ALERT_TITLE_DELETE_CARD"), isPresented: $showingDeleteAlert, presenting: cardToEdit) { card in
                Button(LocalizedStringKey("BUTTON_DELETE_CARD"), role: .destructive) { // "BUTTON_DELETE_CARD" uyarı içindeki silme butonu için de kullanılabilir
                    if let indexSet = indexSet(for: card) {
                        dataManager.deleteCard(at: indexSet)
                    }
                    dismiss()
                }
                Button(LocalizedStringKey("CANCEL"), role: .cancel) {} // "CANCEL" anahtarı
            } message: { _ in
                Text(LocalizedStringKey("ALERT_MESSAGE_DELETE_CARD_CONFIRMATION"))
            }
        }
    }

    static func colorFromString(_ nameOrHex: String) -> Color {
        if nameOrHex.hasPrefix("#") {
            let hex = nameOrHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var int: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&int)
            let a, r, g, b: UInt64
            switch hex.count {
            case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
            case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
            case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
            default: (a, r, g, b) = (255, 0, 0, 0)
            }
            return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
        } else {
            switch nameOrHex.lowercased() {
            case "blue": return .blue
            case "red": return .red
            case "green": return .green
            case "orange": return .orange
            case "purple": return .purple
            default: return .gray
            }
        }
    }

    private func colorToHexString(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }

    private func indexSet(for card: CreditCard) -> IndexSet? {
        if let index = dataManager.cards.firstIndex(where: { $0.id == card.id }) {
            return IndexSet(integer: index)
        }
        return nil
    }

    private func saveCard() {
        let colorString = colorToHexString(pickedColor)
        let card = CreditCard(
            id: cardToEdit?.id ?? UUID(),
            name: cardName,
            lastFourDigits: lastFourDigits,
            dueDate: selectedDay,
            isActive: true,
            color: colorString
        )

        if mode == .add {
            dataManager.addCard(card)
        } else {
            dataManager.updateCard(card)
        }

        let dueDates = DueDateCalculator.calculateDueDates(for: card, referenceDate: Date(), using: holidayService) // referenceDate eklendi
        guard let nextDueDate = dueDates.first else {
            dismiss()
            return
        }
        NotificationManager.shared.scheduleReminder(for: card, dueDate: nextDueDate)
        dismiss()
    }
}
