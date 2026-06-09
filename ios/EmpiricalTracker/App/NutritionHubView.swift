import SwiftUI
import Core

/// Container that lets the user swipe between the three nutrition-related
/// screens (Diary, Plan, Recipes) or tap the segmented picker at the top.
struct NutritionHubView: View {
    @State private var page: NutritionPage = .diary

    var body: some View {
        VStack(spacing: 0) {
            picker
            pageContent
        }
        .background(Color.bgBase.ignoresSafeArea())
    }

    // MARK: - Picker

    private var picker: some View {
        HStack(spacing: 0) {
            ForEach(NutritionPage.allCases) { p in
                Button {
                    withAnimation(.snappy(duration: 0.22)) { page = p }
                } label: {
                    Text(p.title)
                        .font(.system(size: 13, weight: page == p ? .semibold : .regular))
                        .foregroundStyle(page == p ? Color.accent : Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            page == p
                                ? Color.accent.opacity(0.12)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(page == p ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Page content

    @ViewBuilder
    private var pageContent: some View {
        TabView(selection: $page) {
            FoodDiaryView()
                .tag(NutritionPage.diary)
            MealPlanCalendarView()
                .tag(NutritionPage.plan)
            RecipesView()
                .tag(NutritionPage.recipes)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy(duration: 0.22), value: page)
    }
}

// MARK: - Page enum

enum NutritionPage: Int, CaseIterable, Identifiable {
    case diary, plan, recipes

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .diary:   return String(localized: "nutrition.page.diary")
        case .plan:    return String(localized: "nutrition.page.plan")
        case .recipes: return String(localized: "nutrition.page.recipes")
        }
    }
}
