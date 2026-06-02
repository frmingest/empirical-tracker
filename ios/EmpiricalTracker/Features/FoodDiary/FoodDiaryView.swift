import Core
import FoodDiary
import SwiftUI

/// The Diary tab (Sprint 6). A per-day food log with multi-source search, native
/// barcode scanning, and daily totals including sodium and saturated fat.
struct FoodDiaryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: FoodDiaryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: String(localized: "food.loading"))
                }
            }
            .navigationTitle(String(localized: "tab.diary"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                if viewModel == nil {
                    viewModel = FoodDiaryViewModel(repo: env.foodDiary)
                    await viewModel?.load()
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isAddPresented ?? false },
                set: { viewModel?.isAddPresented = $0 }
            )) {
                if let vm = viewModel {
                    FoodSearchSheet(viewModel: vm)
                }
            }
            .alert(
                String(localized: "food.error.title"),
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
        ToolbarItem(placement: .principal) {
            if let vm = viewModel {
                DayNavigator(viewModel: vm)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let vm = viewModel, !vm.isToday {
                Button {
                    Task { await vm.goToToday() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityLabel(String(localized: "food.day.jump_today"))
                }
            }
            Button {
                viewModel?.beginAdd(meal: .breakfast)
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(String(localized: "food.add"))
            }
            .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: FoodDiaryViewModel) -> some View {
        if vm.isLoading && !vm.hasEntries {
            LoadingView(message: String(localized: "food.loading"))
        } else if !vm.hasEntries {
            emptyState(vm)
        } else {
            diaryList(vm)
        }
    }

    private func emptyState(_ vm: FoodDiaryViewModel) -> some View {
        VStack(spacing: 20) {
            EmptyStateView(
                icon: "fork.knife",
                title: String(localized: "food.empty.title"),
                message: String(localized: "food.empty.message")
            )
            Button {
                vm.beginAdd(meal: .breakfast)
            } label: {
                Label(String(localized: "food.add"), systemImage: "plus")
                    .font(.headlineSmall)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func diaryList(_ vm: FoodDiaryViewModel) -> some View {
        List {
            Section {
                DailyTotalsCard(totals: vm.dailyTotals)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            ForEach(Meal.allCases) { meal in
                let mealEntries = vm.entriesByMeal[meal] ?? []
                if !mealEntries.isEmpty {
                    Section {
                        ForEach(mealEntries) { entry in
                            FoodEntryRow(entry: entry)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await vm.delete(entry) }
                                    } label: {
                                        Label(String(localized: "common.delete"), systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        MealSectionHeader(meal: meal) { vm.beginAdd(meal: meal) }
                    }
                }
            }

            Section {
                AttributionFooter()
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load() }
    }
}

// MARK: - Day navigator

private struct DayNavigator: View {
    @Bindable var viewModel: FoodDiaryViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.goToPreviousDay() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(String(localized: "food.day.previous"))

            Text(viewModel.dayTitle)
                .font(.headlineMedium)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 120)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.goToNextDay() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(String(localized: "food.day.next"))
            .disabled(viewModel.isToday)
        }
        .tint(Color.accent)
    }
}

// MARK: - Meal section header

private struct MealSectionHeader: View {
    let meal: Meal
    let onAdd: () -> Void

    var body: some View {
        HStack {
            Label(meal.localizedName, systemImage: meal.icon)
                .font(.headlineSmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accent)
            }
            .accessibilityLabel(Text(String(localized: "food.add.to_meal \(meal.localizedName)")))
        }
    }
}

// MARK: - Daily totals card

private struct DailyTotalsCard: View {
    let totals: DailyTotals

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: 14) {
                // Hero: the day's energy, captioned above so the number never has to
                // share its baseline with a label that pushes it onto a second line.
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "food.totals.title"))
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                    Text(NutritionFormat.energy(totals.energyKcal))
                        .font(.numericLarge)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }

                Divider().background(Color.borderSubtle)

                // Primary macros: one even row of three.
                HStack(spacing: 0) {
                    macro(String(localized: "food.macro.carbs"),   NutritionFormat.grams(totals.carbsG))
                    macro(String(localized: "food.macro.protein"), NutritionFormat.grams(totals.proteinG))
                    macro(String(localized: "food.macro.fat"),     NutritionFormat.grams(totals.fatG))
                }

                // Secondary nutrients inline on one muted line, rather than a second
                // grid row with an empty third cell.
                HStack(spacing: 16) {
                    micro(String(localized: "food.macro.sat_fat"), NutritionFormat.grams(totals.saturatedFatG))
                    micro(String(localized: "food.macro.sodium"),  NutritionFormat.milligrams(totals.sodiumMg))
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func macro(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.numericSmall)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func micro(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(.numericSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .lineLimit(1)
    }
}

// MARK: - Entry row

private struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.foodName)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let source = entry.source {
                    FoodSourceBadge(source: source)
                }
                Spacer()
                Text(NutritionFormat.energy(entry.energyKcal))
                    .font(.numericSmall)
                    .foregroundStyle(Color.textPrimary)
            }

            HStack(spacing: 8) {
                if let brand = entry.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                if let q = entry.quantityG {
                    Text(NutritionFormat.grams(q))
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                Text(macroSummary)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var macroSummary: String {
        NutritionFormat.macroSummary(carbs: entry.carbsG, protein: entry.proteinG, fat: entry.fatG)
    }

    private var accessibilityText: String {
        var parts = [entry.foodName]
        if let source = entry.source { parts.append(source.displayName) }
        parts.append(NutritionFormat.energy(entry.energyKcal))
        return parts.joined(separator: ", ")
    }
}

// MARK: - Attribution footer

private struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "food.attribution.title"))
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
            Text(String(localized: "food.attribution.body"))
                .font(.bodySmall)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    env.foodDiary.entries = MockData.foodEntries
    return FoodDiaryView()
        .environment(env)
}
