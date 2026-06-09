import Core
import SwiftUI
import UIKit

/// Modal form for logging a body measurement (Sprint 8).
/// Every field is optional, but the view model enforces ADR-017's two rules:
/// at least one of weight / waist / blood pressure, and blood pressure both-or-neither.
struct LogBodyMetricSheet: View {
    @Bindable var viewModel: BodyMetricsViewModel

    var body: some View {
        NavigationStack {
            Form {
                dateSection
                metricsSection
                noteSection
                if let error = viewModel.formError {
                    Section {
                        Text(error)
                            .font(.bodySmall)
                            .foregroundStyle(Color.outRange)
                    }
                }
            }
            .navigationTitle(String(localized: "body.form.title"))
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
                    .disabled(!viewModel.isFormValid)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var dateSection: some View {
        Section {
            DatePicker(
                String(localized: "body.form.date"),
                selection: $viewModel.formDate,
                in: ...Date(),
                displayedComponents: .date
            )
        }
    }

    private var metricsSection: some View {
        Section {
            measurementRow(
                String(localized: "body.form.weight"),
                text: $viewModel.formWeight,
                unit: String(localized: "body.unit.kg"),
                keyboard: .decimalPad
            )
            measurementRow(
                String(localized: "body.form.waist"),
                text: $viewModel.formWaist,
                unit: String(localized: "body.unit.cm"),
                keyboard: .decimalPad
            )
            measurementRow(
                String(localized: "body.form.systolic"),
                text: $viewModel.formSystolic,
                unit: String(localized: "body.unit.mmhg"),
                keyboard: .numberPad
            )
            measurementRow(
                String(localized: "body.form.diastolic"),
                text: $viewModel.formDiastolic,
                unit: String(localized: "body.unit.mmhg"),
                keyboard: .numberPad
            )
        } header: {
            Text(String(localized: "body.form.section.metrics"))
        } footer: {
            Text(String(localized: "body.form.hint"))
        }
    }

    private var noteSection: some View {
        Section(String(localized: "body.form.note")) {
            TextField(
                String(localized: "body.form.note.placeholder"),
                text: $viewModel.formNote,
                axis: .vertical
            )
            .lineLimit(2, reservesSpace: false)
        }
    }

    // MARK: - Row builder

    private func measurementRow(
        _ label: String,
        text: Binding<String>,
        unit: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            TextField("—", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityLabel(label)
            Text(unit)
                .foregroundStyle(Color.textMuted)
        }
    }
}

// MARK: - Preview

#Preview {
    PreviewWrapper()
}

private struct PreviewWrapper: View {
    private let env: AppEnvironment
    private let vm: BodyMetricsViewModel

    init() {
        let e = AppEnvironment.preview()
        let m = BodyMetricsViewModel(repo: e.bodyMetrics, dietEventsRepo: e.dietEvents, activityRepo: e.activityMetrics)
        m.isFormPresented = true
        self.env = e
        self.vm = m
    }

    var body: some View {
        LogBodyMetricSheet(viewModel: vm)
            .environment(env)
    }
}
