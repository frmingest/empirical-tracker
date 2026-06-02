import Core
import DietEvents
import SwiftUI

/// Modal sheet for adding a new diet event.
/// Validates label non-empty and endedOn >= startedOn when period.
struct DietEventFormSheet: View {
    @Bindable var viewModel: DietEventViewModel

    var body: some View {
        NavigationStack {
            Form {
                labelSection
                kindSection
                datesSection
                noteSection
                if let err = viewModel.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(Color.outRange)
                            .font(.bodySmall)
                    }
                }
            }
            .navigationTitle(String(localized: "diet_events.form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        viewModel.resetForm()
                        viewModel.isFormPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        Task { await viewModel.submitForm() }
                    }
                    .disabled(!viewModel.formIsValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var labelSection: some View {
        Section(String(localized: "diet_events.form.label")) {
            TextField(
                String(localized: "diet_events.form.label.placeholder"),
                text: $viewModel.formLabel
            )
            .autocorrectionDisabled()
        }
    }

    private var kindSection: some View {
        Section(String(localized: "diet_events.form.kind")) {
            Picker(String(localized: "diet_events.form.kind"), selection: $viewModel.formKind) {
                ForEach(DietEvent.Kind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.icon)
                        .tag(kind)
                }
            }
            .pickerStyle(.wheel)
            .accessibilityLabel(String(localized: "diet_events.form.kind"))
        }
    }

    private var datesSection: some View {
        Section(String(localized: "diet_events.form.dates")) {
            DatePicker(
                String(localized: "diet_events.form.started_on"),
                selection: $viewModel.formStartedOn,
                displayedComponents: .date
            )

            Toggle(String(localized: "diet_events.form.is_period"), isOn: $viewModel.formIsPeriod)

            if viewModel.formIsPeriod {
                DatePicker(
                    String(localized: "diet_events.form.ended_on"),
                    selection: $viewModel.formEndedOn,
                    in: viewModel.formStartedOn...,
                    displayedComponents: .date
                )
                if viewModel.endDateError {
                    Text(String(localized: "diet_events.form.ended_on.error"))
                        .font(.bodySmall)
                        .foregroundStyle(Color.outRange)
                }
            }
        }
    }

    private var noteSection: some View {
        Section(String(localized: "diet_events.form.note")) {
            TextField(
                String(localized: "diet_events.form.note.placeholder"),
                text: $viewModel.formNote,
                axis: .vertical
            )
            .lineLimit(3, reservesSpace: false)
        }
    }
}

// MARK: - DietEvent.Kind display name

extension DietEvent.Kind {
    var displayName: String {
        switch self {
        case .diet:       return String(localized: "diet_events.kind.diet")
        case .fast:       return String(localized: "diet_events.kind.fast")
        case .supplement: return String(localized: "diet_events.kind.supplement")
        case .medication: return String(localized: "diet_events.kind.medication")
        case .lifestyle:  return String(localized: "diet_events.kind.lifestyle")
        case .other:      return String(localized: "diet_events.kind.other")
        }
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    let vm = DietEventViewModel(repo: env.dietEvents)
    vm.isFormPresented = true
    return DietEventFormSheet(viewModel: vm)
        .environment(env)
}
