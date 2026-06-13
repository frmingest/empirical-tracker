import Core
import MealPlans
import SwiftUI

/// The Plan tab (Sprint 7, ADR-012). Redesigned for clarity: a visible plan-scope
/// chip bar makes named plans discoverable, the week strip surfaces per-day energy
/// at a glance, and the selected-day card groups meals by slot (Breakfast / Lunch /
/// Dinner / Snack) with a per-slot add. "Log to diary" is a first-class inline
/// action, and a "How plans work" explainer teaches the model. Multi-week
/// navigation, the named-plan filter and the diary promotion are all preserved.
struct MealPlanCalendarView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: MealPlanViewModel?
    /// The day whose meals are shown in the detail card. Always a member of the
    /// view model's currently-loaded week.
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var isHowItWorksPresented = false

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
                    viewModel = MealPlanViewModel(repo: env.mealPlans, recents: env.recentFoods)
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
            .sheet(isPresented: $isHowItWorksPresented) {
                MealPlanHowItWorksSheet()
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
            Button {
                isHowItWorksPresented = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .accessibilityLabel(String(localized: "plan.howitworks.button"))
            }
            .foregroundStyle(Color.accent)
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
                    // Always shown so "Manage plans" (and creating the first named
                    // plan) stays reachable even before any plan exists.
                    PlanScopeBar(viewModel: vm)

                    WeekOverviewCard(
                        viewModel: vm,
                        selectedDay: $selectedDay,
                        onShift: { offset in await shiftWeek(by: offset, vm: vm) },
                        onToday: { await goToToday(vm) }
                    )

                    if vm.isWeekEmpty {
                        PlanEmptyExplainer(
                            onAdd: { vm.beginAdd(on: selectedDay, meal: .breakfast) },
                            onLearnMore: { isHowItWorksPresented = true }
                        )
                    } else {
                        DayDetailCard(viewModel: vm, day: selectedDay)
                    }

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

// MARK: - Plan scope bar

/// Horizontal chip row that surfaces the named-plan filter (previously buried in a
/// toolbar menu). "All" plus one chip per plan, then a trailing "Manage" button.
private struct PlanScopeBar: View {
    @Bindable var viewModel: MealPlanViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillChip(
                    String(localized: "plan.filter.all"),
                    isSelected: viewModel.selectedPlanId == nil
                ) {
                    withAnimation(.snappy(duration: 0.2)) { viewModel.selectedPlanId = nil }
                }

                ForEach(viewModel.plans) { plan in
                    PillChip(plan.name, isSelected: viewModel.selectedPlanId == plan.id) {
                        withAnimation(.snappy(duration: 0.2)) { viewModel.selectedPlanId = plan.id }
                    }
                }

                Button {
                    viewModel.isPlanManagerPresented = true
                } label: {
                    Label(String(localized: "plan.manage"), systemImage: "folder")
                        .font(.headlineSmall)
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Week overview card

/// Enriched week strip: each day cell shows its number and a compact energy total
/// so the week reads at a glance. Keeps the month header + prev/next/"today".
private struct WeekOverviewCard: View {
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
        let kcal = viewModel.energyTotal(on: day)
        let count = viewModel.mealCount(on: day)

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.headlineMedium)
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday))
                // Compact energy when the day has meals; a fixed-height blank
                // keeps every cell the same size so the grid stays even.
                Text(count > 0 ? compactKcal(kcal) : " ")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
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
        .accessibilityLabel(accessibilityLabel(day: day, count: count, kcal: kcal))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(day: Date, count: Int, kcal: Double) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        guard count > 0 else { return date }
        return "\(date), \(count) meals, \(NutritionFormat.energy(kcal))"
    }

    /// "640" or "1.2k" — keeps the tiny cell label legible.
    private func compactKcal(_ kcal: Double) -> String {
        guard kcal >= 1000 else { return "\(Int(kcal.rounded()))" }
        return "\((kcal / 1000).formatted(.number.precision(.fractionLength(1))))k"
    }

    private func dayColor(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accent }
        return .textPrimary
    }

    private var monthTitle: String { selectedDay.formatted(.dateTime.month(.wide)) }
    private var yearTitle: String { selectedDay.formatted(.dateTime.year()) }
}

// MARK: - Selected day card (grouped by meal slot)

private struct DayDetailCard: View {
    let viewModel: MealPlanViewModel
    let day: Date

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 18) {
                header
                ForEach(viewModel.slots(on: day), id: \.self) { slot in
                    MealSlotSection(viewModel: viewModel, day: day, slot: slot)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headlineLarge)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            let total = viewModel.energyTotal(on: day)
            if total > 0 {
                Text(NutritionFormat.energy(total))
                    .font(.numericSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }
}

// MARK: - Meal slot section

/// One meal slot (Breakfast / Lunch / Dinner / Snack) on a day: a header that
/// colour-codes the slot and totals its energy, a per-slot "+", and the slot's
/// meals (or a slim "add food" prompt when empty).
private struct MealSlotSection: View {
    let viewModel: MealPlanViewModel
    let day: Date
    let slot: Meal

    private var meals: [PlannedMeal] { viewModel.meals(on: day, slot: slot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(slot.localizedName, systemImage: slot.icon)
                    .labelStyle(.titleAndIcon)
                    .font(.headlineSmall)
                    .foregroundStyle(slot.tint)
                Spacer(minLength: 0)
                let kcal = viewModel.energyTotal(on: day, slot: slot)
                if kcal > 0 {
                    Text(NutritionFormat.energy(kcal))
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                }
                Button {
                    viewModel.beginAdd(on: day, meal: slot)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accent)
                }
                .accessibilityLabel(String(localized: "plan.slot.add \(slot.localizedName)"))
            }

            if meals.isEmpty {
                emptyRow
            } else {
                ForEach(meals) { meal in
                    PlannedMealRow(
                        meal: meal,
                        weekDays: viewModel.week.days,
                        onToggleDone: { Task { await viewModel.toggleDone(meal) } },
                        onLogToDiary: { Task { await viewModel.logToDiary(meal) } },
                        onMove: { date, slot in Task { await viewModel.move(meal, toDate: date, slot: slot) } },
                        onDelete: { Task { await viewModel.delete(meal) } }
                    )
                }
            }
        }
    }

    private var emptyRow: some View {
        Button {
            viewModel.beginAdd(on: day, meal: slot)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(String(localized: "plan.meal.add"))
                Spacer()
            }
            .font(.bodySmall)
            .foregroundStyle(Color.textMuted)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Planned meal row

private struct PlannedMealRow: View {
    let meal: PlannedMeal
    let weekDays: [Date]
    let onToggleDone: () -> Void
    let onLogToDiary: () -> Void
    let onMove: (Date, Meal) -> Void
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

            // "Log to diary" promoted to a first-class inline action (was buried
            // in the overflow menu). Dimmed once already logged/done.
            Button(action: onLogToDiary) {
                Image(systemName: "fork.knife")
                    .font(.bodyMedium)
                    .foregroundStyle(meal.done ? Color.textMuted : Color.accent)
                    .frame(width: 32, height: 32)
                    .background((meal.done ? Color.textMuted : Color.accent).opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "plan.log_to_diary"))

            Menu {
                Menu {
                    ForEach(weekDays, id: \.self) { d in
                        Button(d.formatted(.dateTime.weekday(.wide).day())) {
                            onMove(d, meal.meal)
                        }
                    }
                } label: {
                    Label(String(localized: "plan.move.day"), systemImage: "calendar")
                }
                Menu {
                    ForEach([Meal.breakfast, .lunch, .dinner, .snack]) { s in
                        Button {
                            onMove(meal.scheduledOn, s)
                        } label: {
                            Label(s.localizedName, systemImage: s.icon)
                        }
                    }
                } label: {
                    Label(String(localized: "plan.move.meal"), systemImage: "arrow.up.arrow.down")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
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

// MARK: - Empty / first-run explainer

/// Shown when the visible week has no scheduled meals — explains the model in
/// plain language and offers the two next steps (add a meal / learn more).
private struct PlanEmptyExplainer: View {
    let onAdd: () -> Void
    let onLearnMore: () -> Void

    var body: some View {
        SoftCard {
            VStack(spacing: 14) {
                CircleIconBadge("calendar", tint: Color.accent, size: 52)
                Text(String(localized: "plan.empty.explainer.title"))
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(String(localized: "plan.empty.explainer.message"))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAdd) {
                    Label(String(localized: "plan.day.add"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onLearnMore) {
                    Text(String(localized: "plan.howitworks.button"))
                        .font(.bodyMedium)
                        .foregroundStyle(Color.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
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
