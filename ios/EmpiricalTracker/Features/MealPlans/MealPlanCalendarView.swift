import Core
import MealPlans
import SwiftUI

/// The Plan tab (Sprint 7, ADR-012). A Monday→Sunday week of planned meals with
/// multi-week navigation, per-day energy totals, named-plan filtering, and the
/// "Log to diary" promotion that reuses the Sprint 6 food pipeline.
struct MealPlanCalendarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: MealPlanViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: String(localized: "plan.loading"))
                }
            }
            .navigationTitle(String(localized: "tab.plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                if viewModel == nil {
                    viewModel = MealPlanViewModel(repo: env.mealPlans)
                    await viewModel?.load()
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isPickerPresented ?? false },
                set: { viewModel?.isPickerPresented = $0 }
            )) {
                if let vm = viewModel {
                    PlannedMealPickerSheet(viewModel: vm)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isPlanManagerPresented ?? false },
                set: { viewModel?.isPlanManagerPresented = $0 }
            )) {
                if let vm = viewModel {
                    MealPlanManagerSheet(viewModel: vm)
                }
            }
            .alert(
                String(localized: "plan.error.title"),
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
                WeekNavigator(viewModel: vm)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let vm = viewModel, !vm.isCurrentWeek {
                Button {
                    Task { await vm.goToThisWeek() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .accessibilityLabel(String(localized: "plan.week.jump_current"))
                }
            }
            if let vm = viewModel {
                PlanFilterMenu(viewModel: vm)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: MealPlanViewModel) -> some View {
        if vm.isLoading && vm.allMeals.isEmpty {
            LoadingView(message: String(localized: "plan.loading"))
        } else {
            calendarList(vm)
        }
    }

    private func calendarList(_ vm: MealPlanViewModel) -> some View {
        List {
            if vm.isWeekEmpty {
                Section {
                    EmptyStateView(
                        icon: "calendar.badge.plus",
                        title: String(localized: "plan.empty.title"),
                        message: String(localized: "plan.empty.message")
                    )
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(vm.week.days, id: \.self) { day in
                DaySection(viewModel: vm, day: day)
            }

            Section {
                DisclaimerFooter()
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load() }
    }
}

// MARK: - Week navigator

private struct WeekNavigator: View {
    @Bindable var viewModel: MealPlanViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.goToPreviousWeek() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(String(localized: "plan.week.previous"))

            Text(viewModel.weekTitle)
                .font(.headlineMedium)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 120)
                .multilineTextAlignment(.center)

            Button {
                Task { await viewModel.goToNextWeek() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(String(localized: "plan.week.next"))
        }
        .tint(Color.accent)
    }
}

// MARK: - Plan filter menu

private struct PlanFilterMenu: View {
    @Bindable var viewModel: MealPlanViewModel

    var body: some View {
        Menu {
            Picker(String(localized: "plan.filter.title"), selection: $viewModel.selectedPlanId) {
                Text(String(localized: "plan.filter.all")).tag(String?.none)
                ForEach(viewModel.plans) { plan in
                    Text(plan.name).tag(String?.some(plan.id))
                }
            }
            Divider()
            Button {
                viewModel.isPlanManagerPresented = true
            } label: {
                Label(String(localized: "plan.manage"), systemImage: "folder")
            }
        } label: {
            Image(systemName: viewModel.selectedPlanId == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .accessibilityLabel(String(localized: "plan.filter.title"))
        }
        .tint(Color.accent)
    }
}

// MARK: - Day section

private struct DaySection: View {
    @Bindable var viewModel: MealPlanViewModel
    let day: Date

    private var meals: [PlannedMeal] { viewModel.meals(on: day) }

    var body: some View {
        Section {
            if meals.isEmpty {
                Button {
                    viewModel.beginAdd(on: day, meal: .breakfast)
                } label: {
                    Label(String(localized: "plan.day.add"), systemImage: "plus")
                        .font(.bodySmall)
                        .foregroundStyle(Color.accent)
                }
            } else {
                ForEach(meals) { meal in
                    PlannedMealRow(meal: meal) {
                        Task { await viewModel.toggleDone(meal) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await viewModel.delete(meal) }
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                        Button {
                            Task { await viewModel.logToDiary(meal) }
                        } label: {
                            Label(String(localized: "plan.log_to_diary"), systemImage: "fork.knife")
                        }
                        .tint(Color.accent)
                    }
                }
            }
        } header: {
            DayHeader(viewModel: viewModel, day: day, mealCount: meals.count)
        }
    }
}

private struct DayHeader: View {
    let viewModel: MealPlanViewModel
    let day: Date
    let mealCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text(viewModel.dayTitle(day))
                    .font(.headlineSmall)
                    .foregroundStyle(viewModel.isToday(day) ? Color.accent : Color.textSecondary)
                Text(viewModel.daySubtitle(day))
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
            }
            Spacer()
            if mealCount > 0 {
                Text(NutritionFormat.energy(viewModel.energyTotal(on: day)))
                    .font(.numericSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Button {
                viewModel.beginAdd(on: day, meal: .breakfast)
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accent)
            }
            .accessibilityLabel(Text(String(localized: "plan.day.add")))
        }
    }
}

// MARK: - Planned meal row

private struct PlannedMealRow: View {
    let meal: PlannedMeal
    let onToggleDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleDone) {
                Image(systemName: meal.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(meal.done ? Color.inRange : Color.textMuted)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: meal.done ? "plan.meal.done" : "plan.meal.not_done"))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(meal.foodName)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .strikethrough(meal.done, color: Color.textMuted)
                        .lineLimit(1)
                    Spacer()
                    Text(NutritionFormat.energy(meal.energyKcal))
                        .font(.numericSmall)
                        .foregroundStyle(Color.textPrimary)
                }
                HStack(spacing: 8) {
                    Text(meal.meal.localizedName)
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                    if let q = meal.quantityG {
                        Text(NutritionFormat.grams(q))
                            .font(.bodySmall)
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    Text(macroSummary)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var macroSummary: String {
        let c = NutritionFormat.grams(meal.carbsG)
        let p = NutritionFormat.grams(meal.proteinG)
        let f = NutritionFormat.grams(meal.fatG)
        return "C \(c) · P \(p) · F \(f)"
    }

    private var accessibilityText: String {
        var parts = [meal.meal.localizedName, meal.foodName]
        parts.append(NutritionFormat.energy(meal.energyKcal))
        if meal.done { parts.append(String(localized: "plan.meal.done")) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Disclaimer footer

private struct DisclaimerFooter: View {
    var body: some View {
        Text(String(localized: "plan.disclaimer"))
            .font(.bodySmall)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    env.mealPlans.plans = MockData.mealPlans
    env.mealPlans.meals = MockData.plannedMeals
    return MealPlanCalendarView()
        .environment(env)
}
