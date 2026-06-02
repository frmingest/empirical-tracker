import Biomarkers
import Core
import SwiftUI

/// Manual result entry for a single biomarker.
/// Posts to `POST /biomarkers/results/manual` via the repository and refreshes
/// the dashboard data so the new point appears on the trend chart immediately.
struct ManualResultSheet: View {
    let marker: BiomarkerWithSeries
    @Bindable var viewModel: BiomarkerDetailViewModel

    @State private var valueText = ""
    @State private var testedAt = Date.now
    @State private var isSubmitting = false

    @FocusState private var valueFocused: Bool

    private var info: BiomarkerInfo { marker.biomarker }

    private var parsedValue: Double? {
        // Accept both "1.4" and Norwegian "1,4".
        let normalized = valueText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized.trimmingCharacters(in: .whitespaces))
    }

    private var isValid: Bool { parsedValue != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(info.displayName)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if let unit = info.unit {
                            Text(unit)
                                .font(.bodySmall)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                } header: {
                    Text("Marker")
                }

                Section {
                    HStack {
                        TextField("Value", text: $valueText)
                            .keyboardType(.decimalPad)
                            .focused($valueFocused)
                        if let unit = info.unit {
                            Text(unit)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    DatePicker(
                        "Date",
                        selection: $testedAt,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Result")
                } footer: {
                    if !info.refRangeRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Reference: \(info.refRangeRaw)")
                    }
                }
            }
            .navigationTitle("Add result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.isManualEntryPresented = false }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await submit() } }
                            .disabled(!isValid)
                    }
                }
            }
            .alert(
                "Couldn't save",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onAppear { valueFocused = true }
        }
    }

    private func submit() async {
        guard let value = parsedValue else { return }
        isSubmitting = true
        _ = await viewModel.addManualResult(to: marker, value: value, testedAt: testedAt)
        isSubmitting = false
    }
}
