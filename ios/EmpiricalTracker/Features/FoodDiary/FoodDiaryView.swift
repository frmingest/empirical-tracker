import Core
import FoodDiary
import SwiftUI

/// The Diary tab (Sprint 6). A per-day food log with multi-source search, native
/// barcode scanning, and daily totals including sodium and saturated fat.
struct FoodDiaryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: FoodDiaryViewModel?
    @State private var isTargetsPresented = false

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
                    viewModel = FoodDiaryViewModel(
                        repo: env.foodDiary,
                        recents: env.recentFoods,
                        activity: env.loggingActivity
                    )
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
            .sheet(item: Binding(
                get: { viewModel?.editingEntry },
                set: { viewModel?.editingEntry = $0 }
            )) { entry in
                if let vm = viewModel {
                    EditFoodEntrySheet(viewModel: vm, entry: entry)
                }
            }
            .sheet(isPresented: $isTargetsPresented) {
                NutritionTargetsSheet()
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
            // Repetitive diets eat the same meals daily — offer yesterday's log
            // as a one-tap starting point.
            if vm.isToday {
                Button {
                    Task { await vm.copyPreviousDay() }
                } label: {
                    Label(String(localized: "food.copy_yesterday"), systemImage: "doc.on.doc")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func diaryList(_ vm: FoodDiaryViewModel) -> some View {
        List {
            Section {
                DailyTotalsCard(totals: vm.dailyTotals, targets: env.nutritionTargets) {
                    isTargetsPresented = true
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                StreakRecapRow(activity: env.loggingActivity)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
            }

            ForEach(Meal.allCases) { meal in
                let mealEntries = vm.entriesByMeal[meal] ?? []
                if !mealEntries.isEmpty {
                    Section {
                        ForEach(mealEntries) { entry in
                            FoodEntryRow(entry: entry, tint: meal.tint)
                                .contentShape(Rectangle())
                                .onTapGesture { vm.editingEntry = entry }
                                // Faint per-meal wash tints the whole section box so the
                                // eye can separate breakfast / lunch / dinner at a glance.
                                .listRowBackground(meal.tint.opacity(0.09))
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
        .scrollContentBackground(.hidden)
        .background(Color.bgBase)
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
        HStack(spacing: 10) {
            CircleIconBadge(meal.icon, tint: meal.tint, size: 32)
            Text(meal.localizedName)
                .font(.headlineMedium)
                .foregroundStyle(Color.textPrimary)
                .textCase(nil)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accent)
            }
            .accessibilityLabel(Text(String(localized: "food.add.to_meal \(meal.localizedName)")))
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Daily totals card

private struct DailyTotalsCard: View {
    let totals: DailyTotals
    let targets: NutritionTargetsStore
    let onEditTargets: () -> Void

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 16) {
                // Hero row: a circular energy badge beside the day's headline number,
                // with the targets editor reachable from the trailing gauge button.
                HStack(spacing: 16) {
                    CircleIconBadge("flame.fill", tint: .mealBreakfast, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "food.totals.title"))
                            .font(.labelSmall)
                            .foregroundStyle(Color.textMuted)
                        Text(NutritionFormat.energy(totals.energyKcal))
                            .font(.numericLarge)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let target = targets.energyKcal {
                            energyProgress(target: target)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: onEditTargets) {
                        Image(systemName: "gauge.with.needle")
                            .font(.title3)
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityLabel(String(localized: "food.targets.title"))
                }

                // Primary macros as soft tinted pills, read against any targets.
                HStack(spacing: 8) {
                    macroPill(
                        String(localized: "food.macro.carbs"),
                        NutritionFormat.grams(totals.carbsG),
                        tint: .mealLunch,
                        subline: targets.carbsMaxG.map {
                            String(localized: "food.targets.limit \(NutritionFormat.grams($0))")
                        },
                        isOver: targets.carbsMaxG.map { totals.carbsG > $0 } ?? false
                    )
                    macroPill(
                        String(localized: "food.macro.protein"),
                        NutritionFormat.grams(totals.proteinG),
                        tint: .mealDinner,
                        subline: targets.proteinG.map {
                            String(localized: "food.targets.of \(NutritionFormat.grams($0))")
                        }
                    )
                    macroPill(
                        String(localized: "food.macro.fat"),
                        NutritionFormat.grams(totals.fatG),
                        tint: .mealSnack
                    )
                }

                // Secondary nutrients on one muted line.
                HStack(spacing: 16) {
                    micro(String(localized: "food.macro.sat_fat"), NutritionFormat.grams(totals.saturatedFatG))
                    micro(String(localized: "food.macro.sodium"),  NutritionFormat.milligrams(totals.sodiumMg))
                    Spacer(minLength: 0)
                }
            }
        }
        // `.contain` (not `.combine`) so the embedded targets button stays
        // individually reachable by VoiceOver.
        .accessibilityElement(children: .contain)
    }

    /// Thin capsule bar plus an "of …" caption beneath the hero energy figure.
    private func energyProgress(target: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.borderSubtle)
                    Capsule()
                        .fill(Color.accent)
                        .frame(width: geo.size.width * min(1, totals.energyKcal / target))
                }
            }
            .frame(height: 5)
            Text(String(localized: "food.targets.of \(NutritionFormat.energy(target))"))
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.top, 3)
    }

    private func macroPill(
        _ label: String,
        _ value: String,
        tint: Color,
        subline: String? = nil,
        isOver: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(tint)
            Text(value)
                .font(.numericSmall)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subline {
                // Colour alone never carries the signal — an exceeded ceiling pairs
                // the tint change with a warning icon (design-system rule).
                HStack(spacing: 3) {
                    if isOver {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.labelSmall)
                            .foregroundStyle(Color.outRange)
                    }
                    Text(subline)
                        .font(.labelSmall)
                        .foregroundStyle(isOver ? Color.outRange : Color.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

// MARK: - Streak recap row

/// One quiet, muted line of habit feedback under the totals card — a streak when
/// one exists, and how many of the last 7 days had a log. No badges, no levels.
private struct StreakRecapRow: View {
    let activity: LoggingActivityStore

    var body: some View {
        let streak = activity.currentStreak
        let last7 = activity.daysLoggedLast7
        if last7 > 0 {
            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.labelSmall)
                    .foregroundStyle(Color.mealBreakfast)
                    .accessibilityHidden(true)
                if streak >= 2 {
                    Text(String(localized: "food.streak.days \(streak)"))
                        .font(.labelSmall)
                        .foregroundStyle(Color.textSecondary)
                    Text(verbatim: "·")
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                }
                Text(String(localized: "food.streak.week \(last7)"))
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Entry row

private struct FoodEntryRow: View {
    let entry: FoodEntry
    /// Tone of the owning meal section — drawn as a leading accent bar so the row
    /// stays visually tied to its meal even while scrolling.
    var tint: Color = .accent

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 3)

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
