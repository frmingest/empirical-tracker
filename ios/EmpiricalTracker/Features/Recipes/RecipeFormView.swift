import Core
import Recipes
import SwiftUI

/// The recipe-authoring module: a form to create a new recipe (or edit one of your
/// own) and save it to the database via `POST` / `PUT /recipes`. Ingredients and
/// instructions are editable, reorderable-by-deletion lists; blank rows are dropped
/// on save. Sharing into the public catalogue and marking a recipe premium are
/// opt-in switches.
struct RecipeFormView: View {
    let viewModel: RecipesViewModel
    /// When set, the form edits this recipe instead of creating a new one.
    let editing: Recipe?
    /// When set (and `editing` is nil), pre-fills a new recipe from an import preview.
    let prefill: RecipePayload?
    /// When set, called instead of `dismiss()` after a successful save — used by
    /// the import flow to close the whole sheet rather than just pop the nav stack.
    let onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    // Identity
    @State private var title: String
    @State private var category: String
    @State private var imageUrl: String
    @State private var servingSize: String

    // Nutrition (kept as text for decimal-pad entry)
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var fatText: String
    @State private var carbsText: String

    // Lists
    @State private var ingredients: [String]
    @State private var instructions: [String]

    // Extras
    @State private var fact: String
    @State private var isPublic: Bool
    @State private var isPremium: Bool

    @State private var isSaving = false

    init(viewModel: RecipesViewModel, editing: Recipe? = nil, prefill: RecipePayload? = nil, onSave: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.editing = editing
        self.prefill = prefill
        self.onSave = onSave
        _title       = State(initialValue: editing?.title ?? prefill?.title ?? "")
        _category    = State(initialValue: editing?.category ?? prefill?.category ?? "")
        _imageUrl    = State(initialValue: editing?.imageUrl ?? prefill?.imageUrl ?? "")
        _servingSize = State(initialValue: editing?.servingSize ?? prefill?.servingSize ?? "")
        _caloriesText = State(initialValue: Self.fmt(editing?.caloriesKcal ?? prefill?.caloriesKcal))
        _proteinText  = State(initialValue: Self.fmt(editing?.proteinG ?? prefill?.proteinG))
        _fatText      = State(initialValue: Self.fmt(editing?.fatG ?? prefill?.fatG))
        _carbsText    = State(initialValue: Self.fmt(editing?.carbsG ?? prefill?.carbsG))
        // Always keep one empty trailing row so there's a visible field to type into.
        _ingredients  = State(initialValue: (editing?.ingredients ?? prefill?.ingredients ?? []) + [""])
        _instructions = State(initialValue: (editing?.instructions ?? prefill?.instructions ?? []) + [""])
        _fact      = State(initialValue: editing?.fact ?? prefill?.fact ?? "")
        _isPublic  = State(initialValue: editing?.isPublic ?? false)
        _isPremium = State(initialValue: editing?.isPremium ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if prefill != nil && editing == nil {
                    Section {
                        Text(String(localized: "recipes.import.review.footer"))
                            .font(.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                identitySection
                nutritionSection
                listSection(
                    header: String(localized: "recipes.ingredients.title"),
                    footer: String(localized: "recipes.form.ingredients.footer"),
                    addLabel: String(localized: "recipes.form.add_ingredient"),
                    placeholder: String(localized: "recipes.form.ingredient.placeholder"),
                    lines: $ingredients
                )
                listSection(
                    header: String(localized: "recipes.instructions.title"),
                    footer: String(localized: "recipes.form.instructions.footer"),
                    addLabel: String(localized: "recipes.form.add_step"),
                    placeholder: String(localized: "recipes.form.step.placeholder"),
                    lines: $instructions
                )
                factSection
                visibilitySection
            }
            .navigationTitle(navigationTitle)
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
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section(String(localized: "recipes.form.section.identity")) {
            labelledField(String(localized: "recipes.form.field.title"), text: $title)
            categoryField
            labelledField(String(localized: "recipes.form.field.image_url"), text: $imageUrl)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            labelledField(String(localized: "recipes.form.field.serving"), text: $servingSize)
        }
    }

    /// Free-text category with a menu of existing categories as quick fills.
    private var categoryField: some View {
        HStack {
            Text(String(localized: "recipes.form.field.category"))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: $category)
                .multilineTextAlignment(.trailing)
            if !viewModel.categories.isEmpty {
                Menu {
                    ForEach(viewModel.categories, id: \.self) { cat in
                        Button(cat) { category = cat }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundStyle(Color.accent)
                        .accessibilityLabel(String(localized: "recipes.form.category.suggest"))
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            nutrientField(String(localized: "food.macro.energy"), $caloriesText,
                          String(localized: "food.unit.kcal"))
            nutrientField(String(localized: "food.macro.protein"), $proteinText,
                          String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.fat"), $fatText,
                          String(localized: "food.unit.g"))
            nutrientField(String(localized: "food.macro.carbs"), $carbsText,
                          String(localized: "food.unit.g"))
        } header: {
            Text(String(localized: "recipes.nutrition.title"))
        } footer: {
            Text(String(localized: "recipes.form.nutrition.footer"))
        }
    }

    private func listSection(
        header: String,
        footer: String,
        addLabel: String,
        placeholder: String,
        lines: Binding<[String]>
    ) -> some View {
        Section {
            ForEach(lines.wrappedValue.indices, id: \.self) { index in
                // Build the per-row binding explicitly (with a bounds guard for the
                // brief window during a delete animation) rather than relying on a
                // Binding subscript.
                TextField(placeholder, text: Binding(
                    get: { index < lines.wrappedValue.count ? lines.wrappedValue[index] : "" },
                    set: { newValue in
                        guard index < lines.wrappedValue.count else { return }
                        lines.wrappedValue[index] = newValue
                    }
                ), axis: .vertical)
            }
            .onDelete { offsets in
                lines.wrappedValue.remove(atOffsets: offsets)
                if lines.wrappedValue.isEmpty { lines.wrappedValue = [""] }
            }
            Button {
                lines.wrappedValue.append("")
            } label: {
                Label(addLabel, systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accent)
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    private var factSection: some View {
        Section {
            TextField(String(localized: "recipes.form.fact.placeholder"), text: $fact, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text(String(localized: "recipes.fact.title"))
        }
    }

    private var visibilitySection: some View {
        Section {
            Toggle(String(localized: "recipes.form.share_public"), isOn: $isPublic)
                .tint(Color.accent)
            Toggle(String(localized: "recipes.form.premium"), isOn: $isPremium)
                .tint(Color.accent)
        } footer: {
            Text(String(localized: "recipes.form.visibility.footer"))
        }
    }

    // MARK: - Row builders

    private func labelledField(_ label: String, text: Binding<String>) -> some View {
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

    // MARK: - Title

    private var navigationTitle: String {
        if editing != nil {
            return String(localized: "recipes.edit.title")
        }
        if prefill != nil {
            return String(localized: "recipes.import.review.title")
        }
        return String(localized: "recipes.create.title")
    }

    // MARK: - Validation & save

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    private var trimmedCategory: String { category.trimmingCharacters(in: .whitespaces) }

    private var isValid: Bool { !trimmedTitle.isEmpty && !trimmedCategory.isEmpty }

    @MainActor
    private func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }

        let payload = RecipePayload(
            title: trimmedTitle,
            category: trimmedCategory,
            imageUrl: imageUrl.trimmingCharacters(in: .whitespaces).nilIfBlank,
            servingSize: servingSize.trimmingCharacters(in: .whitespaces).nilIfBlank,
            caloriesKcal: parse(caloriesText),
            proteinG: parse(proteinText),
            fatG: parse(fatText),
            carbsG: parse(carbsText),
            ingredients: cleaned(ingredients),
            instructions: cleaned(instructions),
            fact: fact.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            isPublic: isPublic,
            isPremium: isPremium
        )

        let ok: Bool
        if let editing {
            ok = await viewModel.updateRecipe(id: editing.id, payload)
        } else {
            ok = await viewModel.createRecipe(payload)
        }
        if ok { if let onSave { onSave() } else { dismiss() } }
    }

    private func cleaned(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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
    var nilIfBlank: String? { isEmpty ? nil : self }
}
