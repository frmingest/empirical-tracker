import Core
import SwiftUI

/// Final step of scheduling a meal: choose quantity (and, for free-text meals, the
/// optional nutrition). Mirrors `LogFoodSheet` (Sprint 6) but writes a `PlannedMeal`
/// rather than a diary entry. The meal slot was chosen in the picker header.
struct ScheduleMealSheet: View {
    @Bindable var viewModel: MealPlanViewModel
    @Environment(\.dismiss) private var dismiss

    /// Product mode when non-nil; free-text mode when nil.
    let item: FoodItem?

    @State private var freeTextName: String
    @State private var quantityText: String = "100"

    // Free-text manual nutrition (all optional — blank renders as "—").
    @State private var energyText = ""
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""

    @State private var noteText = ""

    // MARK: - Init

    init(viewModel: MealPlanViewModel, item: FoodItem) {
        self.viewModel = viewModel
        self.item = item
        _freeTextName = State(initialValue: item.name)
    }

    init(viewModel: MealPlanViewModel, freeTextName: String) {
        self.viewModel = viewModel
        self.item = nil
        _freeTextName = State(initialValue: freeTextName)
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                quantitySection
                if item != nil {
                    ingredientsSection
                    nutritionPreviewSection
                } else {
                    freeTextNutritionSection
                }
                noteSection
            }
            .navigationTitle(String(localized: "plan.schedule.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "plan.schedule.add")) {
                        Task { await submit() }
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        if let item {
            Section {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.bodyLarge)
                            .foregroundStyle(Color.textPrimary)
                        if let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.bodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Spacer()
                    FoodSourceBadge(source: item.source)
                }
            }
        } else {
            Section(String(localized: "food.log.name")) {
                TextField(String(localized: "food.log.name.placeholder"), text: $freeTextName)
                    .autocorrectionDisabled()
            }
        }
    }

    private var quantitySection: some View {
        Section(String(localized: "food.log.quantity")) {
            HStack {
                TextField(String(localized: "food.log.quantity.placeholder"), text: $quantityText)
                    .keyboardType(.decimalPad)
                Text(String(localized: "food.unit.g"))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// Read-only ingredients list, shown above the nutrition when the product
    /// carries one (product / custom sources). Mirrors `LogFoodSheet`.
    @ViewBuilder
    private var ingredientsSection: some View {
        if let ingredients = item?.ingredients,
           !ingredients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section(String(localized: "food.log.ingredients")) {
                Text(ingredients)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var nutritionPreviewSection: some View {
        Section(String(localized: "food.log.nutrition")) {
            previewRow(String(localized: "food.macro.energy"),  NutritionFormat.energy(scaled(\.energyKcal100g)))
            previewRow(String(localized: "food.macro.carbs"),   NutritionFormat.grams(scaled(\.carbs100g)))
            previewRow(String(localized: "food.macro.protein"), NutritionFormat.grams(scaled(\.protein100g)))
            previewRow(String(localized: "food.macro.fat"),     NutritionFormat.grams(scaled(\.fat100g)))
        }
    }

    private var freeTextNutritionSection: some View {
        Section {
            nutrientField(String(localized: "food.macro.energy"),  $energyText, String(localized: "food.unit.kcal"))
            nutrientField(String(localized: "food.macro.carbs"),   $carbsText,  String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.protein"), $proteinText, String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.fat"),     $fatText,    String(localized: "food.unit.g"))
        } header: {
            Text(String(localized: "food.log.nutrition"))
        } footer: {
            Text(String(localized: "food.log.nutrition.optional"))
        }
    }

    private var noteSection: some View {
        Section(String(localized: "food.log.note")) {
            TextField(String(localized: "food.log.note.placeholder"), text: $noteText, axis: .vertical)
                .lineLimit(2, reservesSpace: false)
        }
    }

    // MARK: - Row builders

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value).font(.numericSmall).foregroundStyle(Color.textPrimary)
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

    // MARK: - Validation & scaling

    private var grams: Double? { Self.parse(quantityText) }

    private var isValid: Bool {
        guard let grams, grams > 0 else { return false }
        if item == nil {
            return !freeTextName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private func scaled(_ keyPath: KeyPath<FoodItem, Double?>) -> Double? {
        guard let item, let grams, let per100g = item[keyPath: keyPath] else { return nil }
        return per100g * grams / 100
    }

    // MARK: - Submit

    private func submit() async {
        guard let grams else { return }
        let note = noteText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : noteText

        if let item {
            await viewModel.schedule(item: item, quantityG: grams, note: note)
        } else {
            await viewModel.scheduleFreeText(
                name: freeTextName.trimmingCharacters(in: .whitespaces),
                quantityG: grams,
                energyKcal: Self.parse(energyText),
                carbsG: Self.parse(carbsText),
                proteinG: Self.parse(proteinText),
                fatG: Self.parse(fatText),
                note: note
            )
        }
        dismiss()
    }

    /// Parses a number, tolerating Norwegian decimal commas.
    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
