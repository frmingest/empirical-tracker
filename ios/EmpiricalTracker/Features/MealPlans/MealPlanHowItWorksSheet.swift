import Core
import SwiftUI

/// A short, plain-language explainer for the Plan tab. Opened from the toolbar
/// "?" or the empty-state "Learn more" so a first-time user understands what a
/// meal plan is and the three things they can do with it.
struct MealPlanHowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id = UUID()
        let icon: String
        let tint: Color
        let title: String
        let body: String
    }

    private var steps: [Step] {
        [
            Step(
                icon: "calendar",
                tint: .accent,
                title: String(localized: "plan.howitworks.step1.title"),
                body: String(localized: "plan.howitworks.step1.body")
            ),
            Step(
                icon: "fork.knife",
                tint: .inRange,
                title: String(localized: "plan.howitworks.step2.title"),
                body: String(localized: "plan.howitworks.step2.body")
            ),
            Step(
                icon: "folder",
                tint: .mealDinner,
                title: String(localized: "plan.howitworks.step3.title"),
                body: String(localized: "plan.howitworks.step3.body")
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(String(localized: "plan.howitworks.intro"))
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(steps) { step in
                        HStack(alignment: .top, spacing: 14) {
                            CircleIconBadge(step.icon, tint: step.tint, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.headlineMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text(step.body)
                                    .font(.bodyMedium)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(24)
            }
            .background(Color.bgBase)
            .navigationTitle(String(localized: "plan.howitworks.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    MealPlanHowItWorksSheet()
}
