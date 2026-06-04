import Core
import SwiftUI

/// Sheet for viewing and editing an existing food diary entry.
/// All stored values (energy, carbs, etc.) are the scaled totals for the logged
/// quantity — they are edited directly without per-100g recalculation.
struct EditFoodEntrySheet: View {
    @Bindable var viewModel: FoodDiaryViewModel
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss

    @State private var foodName: String
    @State private var brand: String
    @State private var meal: Meal
    @State private var quantityText: String
    @State private var energyText: String
    @State private var carbsText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var satFatText: String
    @State private var sodiumText: String
    @State private var noteText: String
    @State private var isSaving = false

    init(viewModel: FoodDiaryViewModel, entry: FoodEntry) {
        self.viewModel = viewModel
        self.entry = entry
        _foodName    = State(initialValue: entry.foodName)
        _brand       = State(initialValue: entry.brand ?? "")
        _meal        = State(initialValue: entry.meal)
        _quantityText = State(initialValue: fmt(entry.quantityG))
        _energyText  = State(initialValue: fmt(entry.energyKcal))
        _carbsText   = State(initialValue: fmt(entry.carbsG))
        _proteinText = State(initialValue: fmt(entry.proteinG))
        _fatText     = State(initialValue: fmt(entry.fatG))
        _satFatText  = State(initialValue: fmt(entry.saturatedFatG))
        _sodiumText  = State(initialValue: fmt(entry.sodiumMg))
        _noteText    = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "food.custom.section.identity")) {
                    editField(String(localized: "food.custom.field.name"), text: $foodName)
                    editField(String(localized: "food.custom.field.brand"), text: $brand)
                }

                Section(String(localized: "food.log.meal")) {
                    Picker(String(localized: "food.log.meal"), selection: $meal) {
                        ForEach(Meal.allCases) { m in
                            Label(m.localizedName, systemImage: m.icon).tag(m)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    numericField(String(localized: "food.log.quantity"),
                                 text: $quantityText,
                                 unit: String(localized: "food.unit.g"))
                } header: {
                    Text(String(localized: "food.log.quantity"))
                }

                Section {
                    numericField(String(localized: "food.macro.energy"),  text: $energyText,  unit: String(localized: "food.unit.kcal"))
                    numericField(String(localized: "food.macro.carbs"),   text: $carbsText,   unit: String(localized: "food.unit.g"))
                    numericField(String(localized: "food.macro.protein"), text: $proteinText, unit: String(localized: "food.unit.g"))
                    numericField(String(localized: "food.macro.fat"),     text: $fatText,     unit: String(localized: "food.unit.g"))
                    numericField(String(localized: "food.macro.sat_fat"), text: $satFatText,  unit: String(localized: "food.unit.g"))
                    numericField(String(localized: "food.macro.sodium"),  text: $sodiumText,  unit: String(localized: "food.unit.mg"))
                } header: {
                    Text(String(localized: "food.custom.section.nutrients"))
                } footer: {
                    Text(String(localized: "food.edit.nutrients.footer"))
                }

                Section(String(localized: "food.log.note")) {
                    TextField(String(localized: "food.log.note.placeholder"),
                              text: $noteText, axis: .vertical)
                        .lineLimit(2, reservesSpace: false)
                }
            }
            .navigationTitle(String(localized: "food.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(String(localized: "common.save")) {
                            Task { await save() }
                        }
                        .disabled(foodName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Row builders

    private func editField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
        }
    }

    private func numericField(_ label: String, text: Binding<String>, unit: String) -> some View {
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

    // MARK: - Save

    @MainActor
    private func save() async {
        isSaving = true
        let payload = FoodEntryUpdatePayload(
            meal: meal,
            foodName: foodName.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
            quantityG: parse(quantityText),
            energyKcal: parse(energyText),
            carbsG: parse(carbsText),
            proteinG: parse(proteinText),
            fatG: parse(fatText),
            saturatedFatG: parse(satFatText),
            sodiumMg: parse(sodiumText),
            note: noteText.trimmingCharacters(in: .whitespaces).nilIfEmpty
        )
        await viewModel.update(entry, payload: payload)
        isSaving = false
        dismiss()
    }

    // MARK: - Helpers

    private func parse(_ text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }
}

private func fmt(_ value: Double?) -> String {
    guard let v = value else { return "" }
    return v.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(v))
        : String(format: "%.1f", v)
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
