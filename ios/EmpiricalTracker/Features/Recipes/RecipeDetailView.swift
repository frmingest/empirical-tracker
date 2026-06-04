import Core
import Recipes
import SwiftUI

/// Full recipe screen: hero image, title + favourite star, an estimated-nutrition
/// card, a tappable ingredients checklist, the orange "Recipe Fact" blurb, and the
/// numbered instruction steps. Ingredient / step checks are local "cooking mode"
/// state — useful while following along, intentionally not persisted.
struct RecipeDetailView: View {
    let recipe: Recipe
    let viewModel: RecipesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var checkedIngredients: Set<Int> = []
    @State private var checkedSteps: Set<Int> = []
    @State private var isEditPresented = false
    @State private var isDeleteConfirmPresented = false

    /// Always render the freshest copy so a favourite toggle / edit shows instantly.
    private var live: Recipe { viewModel.current(recipe) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                RecipeHeroImage(urlString: live.imageUrl)
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 24) {
                    header
                    if hasNutrition { nutritionCard }
                    if !live.ingredients.isEmpty { ingredientsSection }
                    if let fact = live.fact, !fact.isEmpty { factCard(fact) }
                    if !live.instructions.isEmpty { instructionsSection }
                }
                .padding(20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.bgBase)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isEditPresented) {
            RecipeFormView(viewModel: viewModel, editing: live)
        }
        .confirmationDialog(
            String(localized: "recipes.delete.confirm.title"),
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "recipes.delete.confirm.action"), role: .destructive) {
                Task {
                    await viewModel.deleteRecipe(live)
                    dismiss()
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    isEditPresented = true
                } label: {
                    Label(String(localized: "recipes.edit.title"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    isDeleteConfirmPresented = true
                } label: {
                    Label(String(localized: "recipes.delete.title"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(String(localized: "recipes.menu.a11y"))
            }
        }
    }

    // MARK: - Header (title, category, favourite)

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(live.title)
                    .font(.displayMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(live.category)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                if let serving = live.servingSize, !serving.isEmpty {
                    Text(String(localized: "recipes.serving \(serving)"))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                }
            }
            Spacer(minLength: 0)
            favoriteButton
        }
    }

    private var favoriteButton: some View {
        Button {
            Task { await viewModel.toggleFavorite(live) }
        } label: {
            Image(systemName: live.isFavorite ? "star.fill" : "star")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(live.isFavorite ? Color.accent : Color.textSecondary)
                .frame(width: 44, height: 44)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.borderCard, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: live.isFavorite
            ? "recipes.favorite.remove"
            : "recipes.favorite.add"))
    }

    // MARK: - Nutrition

    private var hasNutrition: Bool {
        live.caloriesKcal != nil || live.proteinG != nil
            || live.fatG != nil || live.carbsG != nil
    }

    private var nutritionCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "recipes.nutrition.title"))
                    .font(.headlineMedium)
                    .foregroundStyle(Color.textPrimary)
                HStack(alignment: .top, spacing: 0) {
                    macro(String(localized: "food.macro.energy"), live.caloriesKcal,
                          unit: String(localized: "food.unit.kcal"))
                    macro(String(localized: "food.macro.protein"), live.proteinG,
                          unit: String(localized: "food.unit.g"))
                    macro(String(localized: "food.macro.fat"), live.fatG,
                          unit: String(localized: "food.unit.g"))
                    macro(String(localized: "food.macro.carbs"), live.carbsG,
                          unit: String(localized: "food.unit.g"))
                }
            }
        }
    }

    private func macro(_ label: String, _ value: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
            Text(value.map { "\(Self.format($0)) \(unit)" } ?? "—")
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "recipes.ingredients.title"), count: live.ingredients.count)
            ForEach(live.ingredients.indices, id: \.self) { index in
                ChecklistRow(
                    text: live.ingredients[index],
                    checked: checkedIngredients.contains(index)
                ) {
                    toggle(&checkedIngredients, index)
                }
            }
        }
    }

    // MARK: - Recipe fact

    private func factCard(_ fact: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "recipes.fact.title"))
                .font(.headlineMedium)
                .foregroundStyle(.white)
            Text(fact)
                .font(.bodyLarge)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.96, green: 0.27, blue: 0.35),
                         Color(red: 0.98, green: 0.55, blue: 0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(String(localized: "recipes.instructions.title"), count: live.instructions.count)
            ForEach(live.instructions.indices, id: \.self) { index in
                StepRow(
                    number: index + 1,
                    text: live.instructions[index],
                    checked: checkedSteps.contains(index)
                ) {
                    toggle(&checkedSteps, index)
                }
            }
        }
    }

    // MARK: - Shared bits

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headlineLarge)
                .foregroundStyle(Color.textPrimary)
            Text("(\(count))")
                .font(.bodyMedium)
                .foregroundStyle(Color.textMuted)
        }
    }

    private func toggle(_ set: inout Set<Int>, _ index: Int) {
        if set.contains(index) { set.remove(index) } else { set.insert(index) }
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Checklist row (ingredients)

private struct ChecklistRow: View {
    let text: String
    let checked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(checked ? Color.accent : Color.textMuted)
                Text(text)
                    .font(.bodyLarge)
                    .foregroundStyle(checked ? Color.textMuted : Color.textPrimary)
                    .strikethrough(checked, color: Color.textMuted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Numbered step row (instructions)

private struct StepRow: View {
    let number: Int
    let text: String
    let checked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(checked ? Color.accent : Color.borderCard, lineWidth: 2)
                        .background(Circle().fill(checked ? Color.accent : Color.clear))
                        .frame(width: 28, height: 28)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.headlineSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "recipes.step \(number)"))
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textSecondary)
                    Text(text)
                        .font(.bodyLarge)
                        .foregroundStyle(checked ? Color.textMuted : Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
