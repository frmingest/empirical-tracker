import Core
import SwiftUI

/// Final step of logging a food: choose the meal and quantity (and, for free-text
/// entries, the optional nutrition). Shows a live nutrition preview scaled by grams.
struct LogFoodSheet: View {
    @Bindable var viewModel: FoodDiaryViewModel
    @Environment(\.dismiss) private var dismiss

    /// Product mode when non-nil; free-text mode when nil.
    let item: FoodItem?

    @State private var freeTextName: String
    @State private var meal: Meal
    @State private var quantityText: String = "100"

    // Free-text manual nutrition (all optional — blank renders as "—").
    @State private var energyText = ""
    @State private var carbsText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var satFatText = ""
    @State private var sodiumText = ""

    @State private var noteText = ""

    // MARK: - Init

    init(viewModel: FoodDiaryViewModel, item: FoodItem, initialQuantityG: Double? = nil) {
        self.viewModel = viewModel
        self.item = item
        _freeTextName = State(initialValue: item.name)
        _meal = State(initialValue: viewModel.addTargetMeal)
        if let initialQuantityG {
            _quantityText = State(initialValue: NutritionFormat.quantityField(initialQuantityG))
        }
    }

    init(viewModel: FoodDiaryViewModel, freeTextName: String) {
        self.viewModel = viewModel
        self.item = nil
        _freeTextName = State(initialValue: freeTextName)
        _meal = State(initialValue: viewModel.addTargetMeal)
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                mealSection
                quantitySection
                if item != nil {
                    ingredientsSection
                    nutritionPreviewSection
                } else {
                    freeTextNutritionSection
                }
                noteSection
            }
            .navigationTitle(String(localized: "food.log.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
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

    private var mealSection: some View {
        Section(String(localized: "food.log.meal")) {
            Picker(String(localized: "food.log.meal"), selection: $meal) {
                ForEach(Meal.allCases) { m in
                    Label(m.localizedName, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.menu)
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

    /// Live, scaled nutrition for a product (read-only).
    private var nutritionPreviewSection: some View {
        Section(String(localized: "food.log.nutrition")) {
            previewRow(String(localized: "food.macro.energy"),  NutritionFormat.energy(scaled(\.energyKcal100g)))
            previewRow(String(localized: "food.macro.carbs"),   NutritionFormat.grams(scaled(\.carbs100g)))
            previewRow(String(localized: "food.macro.protein"), NutritionFormat.grams(scaled(\.protein100g)))
            previewRow(String(localized: "food.macro.fat"),     NutritionFormat.grams(scaled(\.fat100g)))
            previewRow(String(localized: "food.macro.sat_fat"), NutritionFormat.grams(scaled(\.saturatedFat100g)))
            previewRow(String(localized: "food.macro.sodium"),  NutritionFormat.milligrams(scaled(\.sodium100g)))
        }
    }

    /// Optional manual nutrition for a free-text entry.
    private var freeTextNutritionSection: some View {
        Section {
            nutrientField(String(localized: "food.macro.energy"),  $energyText, String(localized: "food.unit.kcal"))
            nutrientField(String(localized: "food.macro.carbs"),   $carbsText,  String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.protein"), $proteinText, String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.fat"),     $fatText,    String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.sat_fat"), $satFatText, String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.sodium"),  $sodiumText, String(localized: "food.unit.mg"))
        } header: {
            Text(String(localized: "food.log.nutrition"))
        } footer: {
            Text(String(localized: "food.log.nutrition.optional"))
        }
    }

    /// Read-only ingredients list, shown only when the product carries one.
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

    /// Scales a per-100 g field of the product by the entered grams.
    private func scaled(_ keyPath: KeyPath<FoodItem, Double?>) -> Double? {
        guard let item, let grams, let per100g = item[keyPath: keyPath] else { return nil }
        return per100g * grams / 100
    }

    // MARK: - Submit

    private func submit() async {
        guard let grams else { return }
        let note = noteText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : noteText

        if let item {
            let payload = FoodEntryPayload(
                loggedOn: viewModel.selectedDate,
                meal: meal,
                item: item,
                quantityG: grams,
                note: note
            )
            // Product-backed logs feed the recents buffer for one-tap re-logging.
            await viewModel.log(payload, recentItem: item, quantityG: grams)
        } else {
            let payload = FoodEntryPayload(
                loggedOn: viewModel.selectedDate,
                meal: meal,
                foodName: freeTextName.trimmingCharacters(in: .whitespaces),
                quantityG: grams,
                energyKcal: Self.parse(energyText),
                carbsG: Self.parse(carbsText),
                proteinG: Self.parse(proteinText),
                fatG: Self.parse(fatText),
                saturatedFatG: Self.parse(satFatText),
                sodiumMg: Self.parse(sodiumText),
                note: note
            )
            await viewModel.log(payload)
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
