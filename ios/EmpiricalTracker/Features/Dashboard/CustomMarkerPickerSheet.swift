import Biomarkers
import Core
import SwiftUI

/// Sheet that lets the user hand-pick which biomarkers to show in Custom mode.
/// Mirrors `CustomMarkerModal` in the web dashboard.
struct CustomMarkerPickerSheet: View {
    let allMarkerNames: [String]
    @Binding var selected: Set<String>
    let onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(allMarkerNames, id: \.self) { name in
                Toggle(isOn: Binding(
                    get: { selected.contains(name) },
                    set: { on in
                        if on { selected.insert(name) } else { selected.remove(name) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortBiomarkerLabel(name))
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text(name)
                            .font(.labelSmall)
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }
                .tint(Color.accent)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Custom markers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await onDone()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                selectionSummary
            }
        }
    }

    private var selectionSummary: some View {
        HStack {
            Text(selected.isEmpty ? "No markers selected" : "\(selected.count) selected")
                .font(.labelLarge)
                .foregroundStyle(selected.isEmpty ? Color.outRange : Color.textSecondary)
            Spacer()
            if !selected.isEmpty {
                Button("Clear all") { selected.removeAll() }
                    .font(.labelLarge)
                    .foregroundStyle(Color.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selected: Set<String> = ["LDL-kolesterol", "HDL-kolesterol"]
    CustomMarkerPickerSheet(
        allMarkerNames: MockData.biomarkerSeries.map(\.biomarker.nameNo),
        selected: $selected,
        onDone: {}
    )
}
