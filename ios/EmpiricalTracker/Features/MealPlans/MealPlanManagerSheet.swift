import Core
import MealPlans
import SwiftUI

/// Manage named plans (ADR-012): create new groupings and delete existing ones.
/// Deleting a plan removes only the *label* — its scheduled meals stay on the
/// calendar, un-grouped (`plan_id` is `ON DELETE SET NULL`).
struct MealPlanManagerSheet: View {
    @Bindable var viewModel: MealPlanViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newDescription = ""

    var body: some View {
        NavigationStack {
            Form {
                createSection
                plansSection
            }
            .navigationTitle(String(localized: "plan.manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Create

    private var createSection: some View {
        Section {
            TextField(String(localized: "plan.new.name.placeholder"), text: $newName)
                .autocorrectionDisabled()
            TextField(String(localized: "plan.new.description.placeholder"), text: $newDescription, axis: .vertical)
                .lineLimit(2, reservesSpace: false)
            Button {
                Task { await create() }
            } label: {
                Label(String(localized: "plan.new.add"), systemImage: "plus")
            }
            .disabled(trimmedName.isEmpty)
        } header: {
            Text(String(localized: "plan.new.title"))
        }
    }

    // MARK: - Existing plans

    @ViewBuilder
    private var plansSection: some View {
        Section {
            if viewModel.plans.isEmpty {
                Text(String(localized: "plan.list.empty"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            } else {
                ForEach(viewModel.plans) { plan in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        if let desc = plan.description, !desc.isEmpty {
                            Text(desc)
                                .font(.bodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await viewModel.deletePlan(plan) }
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text(String(localized: "plan.list.title"))
        } footer: {
            Text(String(localized: "plan.delete.footer"))
        }
    }

    // MARK: - Helpers

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() async {
        let desc = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel.createPlan(name: trimmedName, description: desc.isEmpty ? nil : desc)
        newName = ""
        newDescription = ""
    }
}
