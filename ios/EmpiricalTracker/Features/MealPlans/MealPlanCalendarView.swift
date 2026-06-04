import Core
import MealPlans
import SwiftUI

/// The Plan tab (Sprint 7, ADR-012). Redesigned around a calendar-first layout: a
/// rounded week strip sits above a "selected day" card that lists that day's
/// planned meals. Multi-week navigation, per-day energy totals, named-plan
/// filtering and the "Log to diary" promotion (reusing the Sprint 6 food pipeline)
/// are all preserved; only the presentation changed.
struct MealPlanCalendarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: MealPlanViewModel?
    /// The day whose meals are shown in the detail card. Always a member of the
    /// view model's currently-loaded week.
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

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
                    selectedDay = clamp(.now, into: viewModel?.week)
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
        ToolbarItem(placement: .topBarLeading) {
            if let vm = viewModel {
                PlanFilterMenu(viewModel: vm)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel?.beginAdd(on: selectedDay, meal: .breakfast)
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(String(localized: "plan.day.add"))
            }
            .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: MealPlanViewModel) -> some View {
        if vm.isLoading && vm.allMeals.isEmpty {
            LoadingView(message: String(localized: "plan.loading"))
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    WeekCalendarCard(
                        viewModel: vm,
                        selectedDay: $selectedDay,
                        onShift: { offset in await shiftWeek(by: offset, vm: vm) },
                        onToday: { await goToToday(vm) }
                    )

                    SelectedDayCard(viewModel: vm, day: selectedDay)

                    DisclaimerFooter()
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background(Color.bgBase)
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Week navigation (keeps `selectedDay` inside the loaded week)

    private func shiftWeek(by offset: Int, vm: MealPlanViewModel) async {
        let weekday = Calendar.current.component(.weekday, from: selectedDay)
        if offset < 0 { await vm.goToPreviousWeek() } else { await vm.goToNextWeek() }
        selectedDay = vm.week.days.first {
            Calendar.current.component(.weekday, from: $0) == weekday
        } ?? vm.week.start
    }

    private func goToToday(_ vm: MealPlanViewModel) async {
        await vm.goToThisWeek()
        selectedDay = clamp(.now, into: vm.week)
    }

    /// Snaps `date` to the matching day inside `week` (falls back to the week start).
    private func clamp(_ date: Date, into week: PlanWeek?) -> Date {
        guard let week else { return Calendar.current.startOfDay(for: date) }
        let weekday = Calendar.current.component(.weekday, from: date)
        return week.days.first {
            Calendar.current.component(.weekday, from: $0) == weekday
        } ?? week.start
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

// MARK: - Week calendar card

private struct WeekCalendarCard: View {
    let viewModel: MealPlanViewModel
    @Binding var selectedDay: Date
    let onShift: (Int) async -> Void
    let onToday: () async -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        SoftCard {
            VStack(spacing: 16) {
                header
                weekdayLabels
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(viewModel.week.days, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(monthTitle)
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(yearTitle)
                    .font(.labelMedium)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            Button { Task { await onShift(-1) } } label: {
                Image(systemName: "chevron.left").font(.headlineMedium)
            }
            .accessibilityLabel(String(localized: "plan.week.previous"))

            Button { Task { await onShift(1) } } label: {
                Image(systemName: "chevron.right").font(.headlineMedium)
            }
            .accessibilityLabel(String(localized: "plan.week.next"))

            if !viewModel.isCurrentWeek {
                Button(String(localized: "plan.week.jump_current")) {
                    Task { await onToday() }
                }
                .font(.headlineSmall)
            }
        }
        .tint(Color.accent)
    }

    private var weekdayLabels: some View {
        HStack(spacing: 4) {
            ForEach(viewModel.week.days, id: \.self) { day in
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(day)
        let hasMeals = !viewModel.meals(on: day).isEmpty

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.day()))
                    .font(.headlineMedium)
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday))
                Circle()
                    .fill(hasMeals ? (isSelected ? Color.white : Color.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.5), lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func dayColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accent }
        return .textPrimary
    }

    private var monthTitle: String {
        selectedDay.formatted(.dateTime.month(.wide))
    }

    private var yearTitle: String {
        selectedDay.formatted(.dateTime.year())
    }
}

// MARK: - Selected day card

private struct SelectedDayCard: View {
    let viewModel: MealPlanViewModel
    let day: Date

    private var meals: [PlannedMeal] { viewModel.meals(on: day) }

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                if meals.isEmpty {
                    emptyRow
                } else {
                    VStack(spacing: 10) {
                        ForEach(meals) { meal in
                            PlannedMealRow(
                                meal: meal,
                                onToggleDone: { Task { await viewModel.toggleDone(meal) } },
                                onLogToDiary: { Task { await viewModel.logToDiary(meal) } },
                                onDelete: { Task { await viewModel.delete(meal) } }
                            )
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.formatted(.dateTime.day().month(.wide).year()))
                .font(.headlineLarge)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if !meals.isEmpty {
                Text(NutritionFormat.energy(viewModel.energyTotal(on: day)))
                    .font(.numericSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Button {
                viewModel.beginAdd(on: day, meal: .breakfast)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accent)
            }
            .accessibilityLabel(String(localized: "plan.day.add"))
        }
    }

    private var emptyRow: some View {
        Button {
            viewModel.beginAdd(on: day, meal: .breakfast)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                Text(String(localized: "plan.day.add"))
                Spacer()
            }
            .font(.bodyMedium)
            .foregroundStyle(Color.accent)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Planned meal row

private struct PlannedMealRow: View {
    let meal: PlannedMeal
    let onToggleDone: () -> Void
    let onLogToDiary: () -> Void
    let onDelete: () -> Void

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
                    Label {
                        Text(meal.meal.localizedName)
                    } icon: {
                        Image(systemName: meal.meal.icon)
                    }
                    .labelStyle(.titleAndIcon)
                    .font(.labelSmall)
                    .foregroundStyle(meal.meal.tint)
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

            Menu {
                Button {
                    onLogToDiary()
                } label: {
                    Label(String(localized: "plan.log_to_diary"), systemImage: "fork.knife")
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "common.more"))
        }
        // Leading accent bar — colour-codes the meal slot, mirroring the diary's
        // `FoodEntryRow` so the two timelines read as one visual language.
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(meal.meal.tint)
                .frame(width: 3)
                .padding(.vertical, 2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Single-line macro summary in the diary's exact format ("C 8 · P 8 · F 17 g").
    private var macroSummary: String {
        NutritionFormat.macroSummary(carbs: meal.carbsG, protein: meal.proteinG, fat: meal.fatG)
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
