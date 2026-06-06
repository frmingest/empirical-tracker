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
    /// Same key as BodyMetricsView so the user only sets height once.
    @AppStorage("body.heightCm") private var heightCm: Double = 0

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
        // The overlay panels are siblings of BodyMapCanvas via ZStack rather
        // than children via .overlay — this way @Observable changes to
        // env.bodyMetrics do not trigger a BodyMapCanvas layout pass.
        ZStack {
            BodyMapCanvas(
                regions: vm.regions,
                silhouetteOpacity: 0.18,
                bottomReserve: 72
            ) { region in
                selectedRegion = region
            }

            VStack {
                HStack {
                    Spacer()
                    BodyMetricsStatsPanel(
                        metrics: env.bodyMetrics.metrics,
                        heightCm: heightCm > 0 ? heightCm : nil
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    HeartStatsPanel(metrics: env.bodyMetrics.metrics)
                        .padding(.bottom, 96)
                        .padding(.leading, 12)
                    Spacer()
                }
            }

            VStack {
                Spacer()
                BodyMapLegendView()
                    .padding(.bottom, 16)
            }
        }
        .background(Color.bgBase)
    }
}

// MARK: - Health stats panel

/// Compact top-right panel always visible on the body-map dashboard.
/// Rows show "--" when data hasn't loaded yet, which keeps the panel in the
/// view hierarchy so @Observable tracking fires on first render.
struct BodyMetricsStatsPanel: View {
    let metrics: [BodyMetric]
    let heightCm: Double?

    private var sorted: [BodyMetric] { metrics.sorted { $0.measuredOn > $1.measuredOn } }
    private var latestWeight: Double? { sorted.first { $0.weightKg != nil }?.weightKg }
    private var latestWaist: Double?  { sorted.first { $0.waistCm  != nil }?.waistCm  }

    var body: some View {
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
    }

    private struct StatRow {
        let icon: String
        let label: String
        let value: String
    }

    private var rows: [StatRow] {
        let heightVal = heightCm.map { String(format: "%.0f cm", $0) } ?? "--"
        let weightVal = latestWeight.map { String(format: "%.1f kg", $0) } ?? "--"
        let waistVal  = latestWaist.map  { String(format: "%.0f cm", $0) } ?? "--"

        var bmiVal = "--"
        if let hm = heightCm.map({ $0 / 100.0 }), let kg = latestWeight {
            bmiVal = String(format: "%.1f", kg / (hm * hm))
        }

        return [
            StatRow(icon: "ruler",         label: "Height", value: heightVal),
            StatRow(icon: "scalemass",      label: "Weight", value: weightVal),
            StatRow(icon: "circle.dashed",  label: "Waist",  value: waistVal),
            StatRow(icon: "figure.stand",   label: "BMI",    value: bmiVal),
        ]
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

// MARK: - Heart stats panel (bottom-left)

/// Compact panel showing latest resting heart rate and HRV from Apple Watch.
/// Always rendered so @Observable tracking is established on first pass.
struct HeartStatsPanel: View {
    let metrics: [BodyMetric]

    private var sorted: [BodyMetric] { metrics.sorted { $0.measuredOn > $1.measuredOn } }

    private var latestRHR: Int? { sorted.first { $0.restingHeartRateBpm != nil }?.restingHeartRateBpm }
    private var latestHRV: Double? { sorted.first { $0.hrvMs != nil }?.hrvMs }

    private func hrColor(_ bpm: Int?) -> Color {
        guard let bpm else { return .textMuted }
        return (60...100).contains(bpm) ? .inRange : .outRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HeartRow(
                icon: "heart.fill",
                label: "Resting HR",
                value: latestRHR.map { "\($0) BPM" } ?? "--",
                color: hrColor(latestRHR)
            )
            HeartRow(
                icon: "waveform.path.ecg",
                label: "HRV",
                value: latestHRV.map { String(format: "%.0f ms", $0) } ?? "--",
                color: .accent
            )
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
    }
}

private struct HeartRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
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
