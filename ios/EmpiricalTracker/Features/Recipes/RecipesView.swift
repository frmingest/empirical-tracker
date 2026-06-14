import Core
import Recipes
import SwiftUI

/// The Recipes tab: a browsable catalogue of carnivore / low-carb recipes grouped
/// by category, with a category-chip filter, a "free recipes" switch, and a "+"
/// that opens the authoring module. Tapping a card opens ``RecipeDetailView``.
struct RecipesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: RecipesViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: String(localized: "recipes.loading"))
                }
            }
            .navigationTitle(String(localized: "recipes.title"))
            .toolbar { toolbarContent }
            .background(Color.bgBase)
            .navigationDestination(for: Recipe.self) { recipe in
                if let vm = viewModel {
                    RecipeDetailView(recipe: recipe, viewModel: vm)
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = RecipesViewModel(repo: env.recipes)
                    await viewModel?.load()
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isCreatePresented ?? false },
                set: { viewModel?.isCreatePresented = $0 }
            )) {
                if let vm = viewModel {
                    RecipeFormView(viewModel: vm)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isImportPresented ?? false },
                set: { viewModel?.isImportPresented = $0 }
            )) {
                if let vm = viewModel {
                    RecipeImportView(viewModel: vm)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.importedRecipe != nil },
                set: { if !$0 { viewModel?.importedRecipe = nil } }
            )) {
                if let vm = viewModel, let imported = vm.importedRecipe {
                    RecipeFormView(viewModel: vm, prefill: imported)
                }
            }
            .alert(
                String(localized: "recipes.error.title"),
                isPresented: Binding(
                    get: { viewModel?.errorMessage != nil },
                    set: { if !$0 { viewModel?.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    viewModel?.isCreatePresented = true
                } label: {
                    Label(String(localized: "recipes.create.title"), systemImage: "square.and.pencil")
                }
                Button {
                    viewModel?.isImportPresented = true
                } label: {
                    Label(String(localized: "recipes.import.title"), systemImage: "link")
                }
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(String(localized: "recipes.create.title"))
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: RecipesViewModel) -> some View {
        if vm.isLoading && vm.allRecipes.isEmpty {
            LoadingView(message: String(localized: "recipes.loading"))
        } else if vm.allRecipes.isEmpty {
            EmptyStateView(
                icon: "fork.knife",
                title: String(localized: "recipes.empty.title"),
                message: String(localized: "recipes.empty.message"),
                action: .init(label: String(localized: "recipes.create.cta")) { @MainActor in
                    vm.isCreatePresented = true
                }
            )
        } else {
            catalogue(vm)
        }
    }

    private func catalogue(_ vm: RecipesViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FreeRecipesToggle(viewModel: vm)
                CategoryChipRow(viewModel: vm)

                if vm.isEmpty {
                    Text(String(localized: "recipes.filter.empty"))
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    ForEach(vm.sections) { section in
                        RecipeSection(title: section.category, recipes: section.recipes)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
        .refreshable { await vm.load() }
    }
}

// MARK: - Free recipes toggle

private struct FreeRecipesToggle: View {
    @Bindable var viewModel: RecipesViewModel

    var body: some View {
        Toggle(isOn: $viewModel.onlyFree) {
            Text(String(localized: "recipes.only_free"))
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(Color.accent)
        .padding(.top, 8)
    }
}

// MARK: - Category chips

private struct CategoryChipRow: View {
    @Bindable var viewModel: RecipesViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(title: String(localized: "recipes.category.all"), category: nil)
                ForEach(viewModel.categories, id: \.self) { category in
                    chip(title: category, category: category)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, category: String?) -> some View {
        let selected = viewModel.isSelected(category)
        return Button {
            viewModel.selectCategory(category)
        } label: {
            Text(title)
                .font(.headlineSmall)
                .foregroundStyle(selected ? Color.white : Color.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selected ? Color.accent : Color.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.borderCard, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Section

private struct RecipeSection: View {
    let title: String
    let recipes: [Recipe]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headlineLarge)
                .foregroundStyle(Color.textPrimary)

            ForEach(recipes) { recipe in
                NavigationLink(value: recipe) {
                    RecipeCard(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Recipe card

/// A large hero card: image with a bottom gradient, the title overlaid, and a
/// "New!" badge for recently-added recipes — the catalogue's primary element.
struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeHeroImage(urlString: recipe.imageUrl)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 8) {
                Text(recipe.title)
                    .font(.headlineLarge)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if recipe.isNew {
                    NewBadge()
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.borderCard, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            recipe.isNew
                ? String(localized: "recipes.card.a11y.new \(recipe.title)")
                : recipe.title
        )
    }
}

/// Loads a recipe's hero image, falling back to a neutral placeholder while it
/// loads or when no image URL is set.
struct RecipeHeroImage: View {
    let urlString: String?

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.overlay(ProgressView().tint(Color.textMuted))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Color.bgElevated.overlay(
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundStyle(Color.textMuted)
        )
    }
}

/// The blue "New!" capsule badge.
struct NewBadge: View {
    var body: some View {
        Text(String(localized: "recipes.badge.new"))
            .font(.labelLarge)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accent)
            .clipShape(Capsule())
    }
}
