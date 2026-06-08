import Core
import SwiftUI

/// Mandatory review step for a PDF/photo lab import (ADR-032 Phase 1).
///
/// Because the values came from probabilistic extraction, nothing is written
/// until the user checks each row, sets the draw date, and taps Apply.
struct LabImportReviewView: View {
    @Bindable var model: LabImportReviewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        reviewBanner

                        ForEach($model.panels) { $panel in
                            panelCard(panel: $panel)
                        }

                        if let error = model.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.bodySmall)
                                .foregroundStyle(Color.outRange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }

                VStack {
                    Spacer()
                    applyBar
                }
            }
            .navigationTitle("Review import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard", role: .destructive) {
                        Task { await model.discard() }
                    }
                    .foregroundStyle(Color.outRange)
                    .disabled(model.isApplying)
                }
            }
        }
        .interactiveDismissDisabled(model.isApplying)
    }

    // MARK: - Banner

    private var reviewBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checklist")
                .foregroundStyle(Color.accent)
            Text("These values were read from your document. Check each one and set the test date before adding them to your records.")
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Panel

    private func panelCard(panel: Binding<LabImportReviewModel.PanelEdit>) -> some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Test date")
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { panel.wrappedValue.date ?? Date.now },
                            set: { panel.wrappedValue.date = $0 }
                        ),
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }

                if panel.wrappedValue.date == nil {
                    Label("Set a date to include these results", systemImage: "calendar.badge.exclamationmark")
                        .font(.bodySmall)
                        .foregroundStyle(Color.outRange)
                }

                Divider()

                ForEach(panel.results) { $row in
                    rowView(row: $row)
                    if row.id != panel.wrappedValue.results.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func rowView(row: Binding<LabImportReviewModel.Row>) -> some View {
        let r = row.wrappedValue
        return HStack(spacing: 12) {
            Button {
                row.wrappedValue.include.toggle()
            } label: {
                Image(systemName: r.include ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(r.include ? Color.accent : Color.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(r.isQualitative)

            VStack(alignment: .leading, spacing: 2) {
                Text(r.nameNo)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                if let ref = r.refRangeRaw, !ref.isEmpty {
                    Text("Ref \(ref)")
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                }
            }

            Spacer()

            if r.isQualitative {
                // Qualitative results can't be stored in Phase 1 — show, don't apply.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.qualitativeText ?? "—")
                        .font(.numericSmall)
                        .foregroundStyle(Color.textSecondary)
                    Text("Not yet supported")
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                HStack(spacing: 4) {
                    TextField("Value", text: row.valueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.numericSmall)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: 80)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.bgBase)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if let unit = r.unit, !unit.isEmpty {
                        Text(unit)
                            .font(.bodySmall)
                            .foregroundStyle(Color.textMuted)
                    }
                }
            }
        }
        .opacity(r.include || r.isQualitative ? 1 : 0.5)
    }

    // MARK: - Apply bar

    private var applyBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await model.apply() }
            } label: {
                if model.isApplying {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text(model.selectedCount > 0
                         ? "Add \(model.selectedCount) result\(model.selectedCount == 1 ? "" : "s")"
                         : "Add results")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canApply || model.isApplying)
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }
}
