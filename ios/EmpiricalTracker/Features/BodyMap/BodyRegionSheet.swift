import Biomarkers
import Core
import SwiftUI

/// Bottom sheet listing all biomarker results for a tapped body region.
struct BodyRegionSheet: View {
    let region: BodyRegion
    var onSelectMarker: (BiomarkerWithSeries) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if region.items.isEmpty {
                    emptyState
                } else {
                    markerList
                }
            }
            .navigationTitle(region.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var markerList: some View {
        List(region.items) { item in
            Button {
                dismiss()
                onSelectMarker(item)
            } label: {
                MarkerRow(item: item)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: region.systemImage,
            title: "No results yet",
            message: "Import a blood panel to see \(region.label) markers here."
        )
        .padding()
    }
}

// MARK: - Marker row

private struct MarkerRow: View {
    let item: BiomarkerWithSeries

    private var assessment: MarkerSignals.Assessment {
        MarkerSignals.assessment(for: item)
    }

    var body: some View {
        HStack(spacing: 12) {
            assessmentDot
            VStack(alignment: .leading, spacing: 2) {
                Text(item.biomarker.displayName)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                if let latest = item.latestResult {
                    Text(valueText(latest))
                        .font(.numericSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var assessmentDot: some View {
        Circle()
            .fill(assessment.color)
            .frame(width: 10, height: 10)
    }

    private func valueText(_ point: ResultPoint) -> String {
        let v = point.value.formatted(.number.precision(.fractionLength(0...2)))
        if let unit = item.biomarker.unit {
            return "\(v) \(unit)"
        }
        return v
    }
}

// MARK: - Assessment color

private extension MarkerSignals.Assessment {
    var color: Color {
        switch self {
        case .inRange:    return .inRange
        case .outOfRange: return .outRange
        case .watch:      return Color.orange
        case .unknown:    return Color.textMuted
        }
    }
}
