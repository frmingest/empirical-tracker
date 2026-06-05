import Biomarkers
import BodyMetrics
import Core
import SwiftUI

/// Inline body-map panel rendered inside the Dashboard's NavigationStack.
/// Tapping a region pushes CategoryGraphsView rather than showing a modal sheet.
struct DashboardBodyMapView: View {
    @Environment(AppEnvironment.self) private var env

    var onSelectCategory: (BiomarkerCategory) -> Void
    var onSelectMarker: (BiomarkerWithSeries) -> Void

    @State private var viewModel: BodyMapViewModel?
    @State private var selectedRegion: BodyRegion?

    var body: some View {
        Group {
            if let vm = viewModel {
                if vm.isLoading {
                    LoadingView(message: "Loading biomarkers…")
                } else {
                    bodyCanvas(vm)
                }
            } else {
                LoadingView(message: "Loading biomarkers…")
            }
        }
        .task {
            if viewModel == nil {
                viewModel = BodyMapViewModel(biomarkersRepo: env.biomarkers)
            }
            await viewModel?.load()
            await env.bodyMetrics.load()
        }
        .sheet(item: $selectedRegion) { region in
            BodyRegionSheet(region: region) { marker in
                onSelectMarker(marker)
            }
        }
    }

    // MARK: - Canvas

    private func bodyCanvas(_ vm: BodyMapViewModel) -> some View {
        BodyMapCanvas(
            regions: vm.regions,
            silhouetteOpacity: 0.18,
            bottomReserve: 72
        ) { region in
            selectedRegion = region
        }
        .overlay(alignment: .topTrailing) {
            BodyMetricsStatsPanel(
                metrics: env.bodyMetrics.metrics,
                heightCm: env.userProfile.heightCm
            )
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .overlay(alignment: .bottom) {
            BodyMapLegendView()
                .padding(.bottom, 16)
        }
        .background(Color.bgBase)
    }
}

// MARK: - Health stats panel

/// Compact top-right panel showing the most-recent body metric readings drawn
/// from the user's logged/synced data (weight, height, waist, blood pressure).
/// Rows with no data are omitted so the card stays small.
struct BodyMetricsStatsPanel: View {
    let metrics: [BodyMetric]
    let heightCm: Double?

    private var latest: BodyMetric? {
        metrics.sorted { $0.measuredOn > $1.measuredOn }.first
    }

    var body: some View {
        let rows = buildRows()
        if rows.isEmpty { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.label) { row in
                    BodyMetricsStatRow(icon: row.icon, label: row.label, value: row.value)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.borderSubtle.opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            .frame(maxWidth: 140)
        )
    }

    private struct StatRow {
        let icon: String
        let label: String
        let value: String
    }

    private func buildRows() -> [StatRow] {
        var rows: [StatRow] = []
        if let cm = heightCm {
            rows.append(.init(icon: "ruler", label: "Height", value: formatHeight(cm)))
        }
        if let kg = latest?.weightKg {
            rows.append(.init(icon: "scalemass", label: "Weight", value: String(format: "%.1f kg", kg)))
        }
        if let cm = latest?.waistCm {
            rows.append(.init(icon: "circle.dashed", label: "Waist", value: String(format: "%.0f cm", cm)))
        }
        if let heightM = heightCm.map({ $0 / 100.0 }), let kg = latest?.weightKg {
            let bmi = kg / (heightM * heightM)
            rows.append(.init(icon: "figure.stand", label: "BMI", value: String(format: "%.1f", bmi)))
        }
        if let sys = latest?.systolic, let dia = latest?.diastolic {
            rows.append(.init(icon: "heart.fill", label: "BP", value: "\(sys)/\(dia)"))
        }
        return rows
    }

    private func formatHeight(_ cm: Double) -> String {
        String(format: "%.0f cm", cm)
    }
}

private struct BodyMetricsStatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
                Text(value)
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

// MARK: - Legend

struct BodyMapLegendView: View {
    var body: some View {
        HStack(spacing: 14) {
            BodyMapLegendItem(color: .inRange,      label: "In range")
            BodyMapLegendItem(color: .orange,       label: "Watch")
            BodyMapLegendItem(color: .outRange,     label: "Out of range")
            BodyMapLegendItem(color: Color.textMuted, label: "No data")
        }
        .font(.labelSmall)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct BodyMapLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Color.textSecondary)
        }
    }
}
