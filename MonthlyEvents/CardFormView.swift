import SwiftUI

struct CardFormView: View {
    // MARK: - Environment & State
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) var currentLocale

    @ObservedObject var dataManager: CardDataManager
    @ObservedObject var holidayService: HolidayService // HolidayService'i dinliyoruz
    @State private var cardName: String
    @State private var lastFourDigits: String
    @State private var selectedDay: Int
    @State private var pickedColor: Color
    @State private var showingDeleteAlert = false
    @State private var paymentDueDaysOffset: Int
    @State private var selectedPaymentType: PaymentType
    @State private var totalLoanInstallments: Int
    @State private var selectedBillingCycle: BillingCycle
    @State private var selectedAnnualBillingMonth: Int
    let cardToEdit: CreditCard?

    // MARK: - Computed Properties
    private var mode: FormMode {
        cardToEdit == nil ? .add : .edit
    }

    private var isSaveButtonDisabled: Bool {
        cardName.isEmpty || (selectedPaymentType == .card && lastFourDigits.count != 4)
    }

    private var navigationTitle: LocalizedStringKey {
        mode == .add ? "NAV_TITLE_ADD_ITEM" : "NAV_TITLE_EDIT_ITEM"
    }
    enum FormMode {
        case add, edit
    }
    // MARK: - Initializer
    init(dataManager: CardDataManager, holidayService: HolidayService, cardToEdit: CreditCard? = nil) {
        self.dataManager = dataManager
        self.holidayService = holidayService
        self.cardToEdit = cardToEdit
        _cardName = State(initialValue: cardToEdit?.name ?? "")
        _lastFourDigits = State(initialValue: cardToEdit?.lastFourDigits ?? "")
        _selectedDay = State(initialValue: cardToEdit?.dueDate ?? 1)
        let initialType = cardToEdit?.type ?? .card
        _selectedPaymentType = State(initialValue: initialType)
        _paymentDueDaysOffset = State(initialValue: cardToEdit?.paymentDueDaysOffset ?? initialType.defaultPaymentDueDaysOffset)

        _totalLoanInstallments = State(initialValue: cardToEdit?.totalInstallments ?? 12)
        _selectedBillingCycle = State(initialValue: cardToEdit?.billingCycle ?? .monthly) // Düzeltilen satır
        _selectedAnnualBillingMonth = State(initialValue: cardToEdit?.annualBillingMonth ?? 1)
        let initialColorString = cardToEdit?.color ?? "blue"
        _pickedColor = State(initialValue: Self.colorFromString(initialColorString))
    }
    // MARK: - Body
    var body: some View {
        NavigationView {
            Form {
                generalInfoSection
                paymentDetailsSection
                settingsSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedStringKey("SAVE")) {
                        saveItem()
                    }
                    .disabled(isSaveButtonDisabled)
                    .fontWeight(.semibold)
                }
            }
            .alert(Text(LocalizedStringKey("ALERT_TITLE_DELETE_ITEM")), isPresented: $showingDeleteAlert) {
                alertButtons
            } message: {
                alertMessage
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color(.systemGray6))
            .onTapGesture {
                self.hideKeyboard()
            }
        }
        .navigationViewStyle(.stack)
    }
}
// MARK: - Subviews
private extension CardFormView {

    var generalInfoSection: some View {
        Section(LocalizedStringKey("SECTION_GENERAL_INFO")) {
            Picker(LocalizedStringKey("PICKER_PAYMENT_TYPE_LABEL"), selection: $selectedPaymentType) {
                ForEach(PaymentType.allCases) { type in
                    Text(LocalizedStringKey(type.localizationKey)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedPaymentType) { newType in
                paymentDueDaysOffset = newType.defaultPaymentDueDaysOffset
                if newType == .subscription {
                    selectedBillingCycle = .monthly
                }
            }
            TextField(LocalizedStringKey("TEXTFIELD_ITEM_NAME_PLACEHOLDER"), text: $cardName)
            if selectedPaymentType == .card {
                TextField(LocalizedStringKey("TEXTFIELD_LAST_FOUR_DIGITS_PLACEHOLDER"), text: $lastFourDigits)
                    .keyboardType(.numberPad)
                    .onChange(of: lastFourDigits) { newValue in
                        let filtered = newValue.filter { "0123456789".contains($0) }
                        lastFourDigits = String(filtered.prefix(4))
                    }
            }
        }
    }

    var paymentDetailsSection: some View {
        Section(LocalizedStringKey("SECTION_PAYMENT_DETAILS")) {
            VStack(alignment: .leading) {
                Text(LocalizedStringKey("PICKER_DAY_OF_MONTH_LABEL"))
                    .font(.headline)
                Picker("", selection: $selectedDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .padding(.horizontal, 40)
            }

            if selectedPaymentType == .card {
                VStack(alignment: .leading) {
                    Text(LocalizedStringKey("STEPPER_PAYMENT_DUE_OFFSET_LABEL"))
                        .font(.headline)
                    Picker("", selection: $paymentDueDaysOffset) {
                        ForEach(0...30, id: \.self) { offset in
                            Text("\(offset)").tag(offset)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .padding(.horizontal, 40)
                }
            }
            if selectedPaymentType == .loan {
                VStack(alignment: .leading) {
                    Text(LocalizedStringKey("STEPPER_LOAN_INSTALLMENTS_LABEL"))
                        .font(.headline)
                    Picker("", selection: $totalLoanInstallments) {
                        ForEach(1...120, id: \.self) { installment in
                            Text("\(installment)").tag(installment)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 100)
                    .padding(.horizontal, 40)
                }
            }
            if selectedPaymentType == .subscription {
                Picker(LocalizedStringKey("PICKER_BILLING_CYCLE_LABEL"), selection: $selectedBillingCycle) {
                    ForEach(BillingCycle.allCases) { cycle in
                        Text(LocalizedStringKey(cycle.localizationKey)).tag(cycle)
                    }
                }
                .pickerStyle(.segmented)
                if selectedBillingCycle == .annually {
                    VStack(alignment: .leading) {
                        Text(LocalizedStringKey("STEPPER_ANNUAL_BILLING_MONTH_LABEL"))
                            .font(.headline)
                        Picker("", selection: $selectedAnnualBillingMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(localizedMonthName(month: month, locale: currentLocale)).tag(month)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 100)
                        .padding(.horizontal, 40)
                    }
                }
            }
        }
    }

    var settingsSection: some View {
        Group {
            Section(LocalizedStringKey("SECTION_ITEM_COLOR")) {
                ColorPicker(LocalizedStringKey("COLORPICKER_SELECT_COLOR_LABEL"), selection: $pickedColor, supportsOpacity: false)
            }
            if mode == .edit {
                Section {
                    Button(LocalizedStringKey("BUTTON_DELETE_ITEM"), role: .destructive) {
                        showingDeleteAlert = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    var alertButtons: some View {
        Button(role: .destructive) {
            if let itemToDelete = cardToEdit {
                dataManager.delete(card: itemToDelete)
                dismiss()
            }
        } label: {
            Text(LocalizedStringKey("BUTTON_DELETE_ITEM"))
        }

        Button(role: .cancel) { } label: {
            Text(LocalizedStringKey("CANCEL"))
        }
    }

    var alertMessage: some View {
        Text(LocalizedStringKey("ALERT_MESSAGE_DELETE_ITEM_CONFIRMATION"))
    }
}
// MARK: - Logic & Helper Functions
private extension CardFormView {

    func saveItem() {
        let colorString = colorToHexString(pickedColor)

        if var card = cardToEdit { // Edit Mode
            card.name = cardName
            card.lastFourDigits = lastFourDigits
            card.dueDate = selectedDay
            card.paymentDueDaysOffset = paymentDueDaysOffset
            card.color = colorString

            if card.type != selectedPaymentType {
                card.type = selectedPaymentType
                card.totalInstallments = nil
                card.remainingInstallments = nil
                card.creationDate = nil
                card.billingCycle = nil
                card.annualBillingMonth = nil
                if selectedPaymentType == .loan {
                    card.totalInstallments = totalLoanInstallments
                    card.remainingInstallments = totalLoanInstallments
                    card.creationDate = Date()
                } else if selectedPaymentType == .subscription {
                    card.billingCycle = selectedBillingCycle
                    card.annualBillingMonth = selectedBillingCycle == .annually ? selectedAnnualBillingMonth : nil
                }
            } else {
                if selectedPaymentType == .loan {
                    let oldTotal = card.totalInstallments ?? 0
                    let oldRemaining = card.remainingInstallments ?? 0
                    let paymentsMade = oldTotal - oldRemaining

                    card.totalInstallments = totalLoanInstallments
                    card.remainingInstallments = max(0, totalLoanInstallments - paymentsMade)
                } else if selectedPaymentType == .subscription {
                    card.billingCycle = selectedBillingCycle
                    card.annualBillingMonth = selectedBillingCycle == .annually ? selectedAnnualBillingMonth : nil
                }
            }

            dataManager.updateCard(card)

        } else { // Add Mode
            var newCard = CreditCard(
                name: cardName,
                lastFourDigits: selectedPaymentType == .card ? lastFourDigits : "",
                dueDate: selectedDay,
                paymentDueDaysOffset: paymentDueDaysOffset,
                color: colorString,
                type: selectedPaymentType
            )

            if selectedPaymentType == .loan {
                newCard.totalInstallments = totalLoanInstallments
                newCard.remainingInstallments = totalLoanInstallments
                newCard.creationDate = Date()
            } else if selectedPaymentType == .subscription {
                newCard.billingCycle = selectedBillingCycle
                newCard.annualBillingMonth = selectedBillingCycle == .annually ? selectedAnnualBillingMonth : nil
            }

            dataManager.addCard(newCard)
        }

        // ÇÖZÜMÜN 1. ADIMI:
        // Değişiklik olsun ya da olmasın, arayüzün yenilenmesi için sinyal gönder.
        holidayService.refresh()

        dismiss()
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
    func colorToHexString(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
    private func localizedMonthName(month: Int, locale: Locale) -> String {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = month
        if let date = calendar.date(from: components) {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = locale
            dateFormatter.dateFormat = "MMMM" // Ayın tam adı
            return dateFormatter.string(from: date)
        }
        return ""
    }
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
