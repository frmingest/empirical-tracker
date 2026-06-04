import Core
import FoodDiary
import SwiftUI

/// Form for reviewing, editing, and saving a food to the user's custom catalogue.
/// Pre-filled from a ``ParsedLabel`` (OCR path) or barcode (manual path). After saving,
/// the resulting `FoodItem` is forwarded to `LogFoodSheet` for quantity entry.
struct AddCustomFoodView: View {
    @Bindable var viewModel: FoodDiaryViewModel
    @Environment(\.dismiss) private var dismiss

    /// Optional pre-parsed label data from the OCR flow.
    let parsedLabel: ParsedLabel?
    /// Optional barcode pre-filled from the barcode-miss flow.
    let prefilledBarcode: String?
    /// Called after the food is saved and logged — used by NutritionLabelCaptureView
    /// to dismiss the entire fullScreenCover chain. Optional (manual entry path).
    var onSaved: (() -> Void)? = nil

    // Form fields
    @State private var foodName: String
    @State private var brand: String
    @State private var barcodeText: String
    @State private var energyText: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var satFatText: String
    @State private var sodiumText: String
    @State private var servingText: String
    /// Explicit opt-in to share this food into the common catalogue. Off by
    /// default — sharing is a deliberate choice and the consent basis for keeping
    /// the item (anonymised) after deletion (ADR-027).
    @State private var shareToCatalogue = false

    @State private var isSaving = false
    @State private var savedItem: FoodItem?
    /// Surfaced as an alert so a failed save is never silent (e.g. a 5xx when the
    /// custom_foods table/migration is missing, or a decode mismatch).
    @State private var errorMessage: String?

    init(
        viewModel: FoodDiaryViewModel,
        parsedLabel: ParsedLabel? = nil,
        prefilledBarcode: String? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.parsedLabel = parsedLabel
        self.prefilledBarcode = prefilledBarcode
        self.onSaved = onSaved

        // Pre-fill from OCR result when available.
        _foodName    = State(initialValue: parsedLabel?.foodName ?? "")
        _brand       = State(initialValue: parsedLabel?.brand ?? "")
        _barcodeText = State(initialValue: prefilledBarcode ?? "")
        _energyText  = State(initialValue: Self.fmt(parsedLabel?.energyKcal100g))
        _carbsText   = State(initialValue: Self.fmt(parsedLabel?.carbs100g))
        _proteinText = State(initialValue: Self.fmt(parsedLabel?.protein100g))
        _fatText     = State(initialValue: Self.fmt(parsedLabel?.fat100g))
        _satFatText  = State(initialValue: Self.fmt(parsedLabel?.saturatedFat100g))
        _sodiumText  = State(initialValue: Self.fmt(parsedLabel?.sodiumMg100g))
        _servingText = State(initialValue: "100")
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                nutrientsSection
                sharingSection
                ocrHintSection
            }
            .onAppear {
                print("🔍 OCR-DEBUG form-appear energy=\(energyText) carbs=\(carbsText) protein=\(proteinText) fat=\(fatText) sodium=\(sodiumText)")
            }
            .navigationTitle(String(localized: "food.custom.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(String(localized: "food.custom.save")) {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
            // Navigate into LogFoodSheet once the item is saved. The whole capture
            // flow is dismissed via `onSaved` only AFTER LogFoodSheet closes — calling
            // it during `save()` would tear down this hierarchy before LogFoodSheet
            // could present, so the diary entry (food_entries row) would never be written.
            .sheet(item: $savedItem, onDismiss: { onSaved?() }) { item in
                LogFoodSheet(viewModel: viewModel, item: item)
            }
            .alert(
                String(localized: "food.label.error.title"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section(String(localized: "food.custom.section.identity")) {
            field(String(localized: "food.custom.field.name"), text: $foodName)
            field(String(localized: "food.custom.field.brand"), text: $brand)
            field(String(localized: "food.custom.field.barcode"), text: $barcodeText)
                .keyboardType(.numberPad)
        }
    }

    private var nutrientsSection: some View {
        Section {
            nutrientField(String(localized: "food.macro.energy"),  $energyText,  String(localized: "food.unit.kcal"))
            nutrientField(String(localized: "food.macro.carbs"),   $carbsText,   String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.protein"), $proteinText, String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.fat"),     $fatText,     String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.sat_fat"), $satFatText,  String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.sodium"),  $sodiumText,  String(localized: "food.unit.mg"))
        } header: {
            Text(String(localized: "food.custom.section.nutrients"))
        } footer: {
            Text(String(localized: "food.custom.nutrients.footer"))
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle(isOn: $shareToCatalogue) {
                Text(String(localized: "food.custom.share.toggle"))
                    .foregroundStyle(Color.textPrimary)
            }
        } footer: {
            Text(String(localized: "food.custom.share.footer"))
        }
    }

    @ViewBuilder
    private var ocrHintSection: some View {
        if parsedLabel != nil {
            Section {
                Label(String(localized: "food.custom.ocr.hint"), systemImage: "sparkles")
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    // MARK: - Row builders

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
        }
    }

    private func nutrientField(_ label: String, _ text: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Validation & save

    private var trimmedName: String { foodName.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool { !trimmedName.isEmpty }

    @MainActor
    private func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }

        let payload = CustomFoodPayload(
            foodName: trimmedName,
            brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            barcode: barcodeText.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            energyKcal: parse(energyText),
            carbsG: parse(carbsText),
            proteinG: parse(proteinText),
            fatG: parse(fatText),
            saturatedFatG: parse(satFatText),
            sodiumMg: parse(sodiumText),
            servingG: parse(servingText),
            isPublic: shareToCatalogue
        )
        print("🔍 OCR-DEBUG payload energy=\(payload.energyKcal as Any) carbs=\(payload.carbsG as Any) protein=\(payload.proteinG as Any) fat=\(payload.fatG as Any)")

        do {
            let record = try await viewModel.createCustomFood(payload)
            // Present LogFoodSheet to capture quantity and write the diary row. The
            // capture flow is dismissed from the sheet's onDismiss, not here.
            savedItem = record.toFoodItem()
        } catch {
            // Surface the failure to the user instead of silently dropping it.
            errorMessage = error.localizedDescription
        }
    }

    private func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    private static func fmt(_ value: Double?) -> String {
        guard let v = value else { return "" }
        return v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
