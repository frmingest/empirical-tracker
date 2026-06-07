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
        // All overlay elements are explicit ZStack siblings rather than .overlay
        // children of BodyMapCanvas (a GeometryReader). Overlays on GeometryReader
        // can silently fail to render inside NavigationStack. Siblings avoid that
        // and also prevent @Observable bodyMetrics updates from triggering a canvas
        // layout pass.
        let hasYearFilter = vm.availableYears.count > 1

        return ZStack {
            BodyMapCanvas(
                regions: vm.regions,
                silhouetteOpacity: 0.18,
                bottomReserve: 80
            ) { region in
                selectedRegion = region
            }

            // Top: stat panels + compact year-filter chips below them
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    HeartStatsPanel(metrics: env.bodyMetrics.metrics)
                        .padding(.top, 12)
                        .padding(.leading, 12)
                    Spacer()
                    BodyMetricsStatsPanel(
                        metrics: env.bodyMetrics.metrics,
                        heightCm: heightCm > 0 ? heightCm : nil
                    )
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
                if hasYearFilter {
                    yearFilterRow(vm).padding(.top, 8)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom: colour legend + last-sync caption.
            // Uses an inner Spacer for bottom inset — .padding after
            // .frame(maxHeight: .infinity) would push content outside the ZStack.
            VStack(spacing: 0) {
                Spacer()
                BodyMapLegendView()
                if let date = env.healthSyncState.lastSyncDate {
                    Text("Synced \(date.formatted(.relative(presentation: .named)))")
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                        .padding(.top, 4)
                }
                Spacer().frame(height: 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }

    private func yearFilterRow(_ vm: BodyMapViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                BodyMapYearChip(label: "All", isSelected: vm.filterYear == nil) {
                    vm.setFilterYear(nil)
                }
                ForEach(vm.availableYears, id: \.self) { year in
                    BodyMapYearChip(label: "\(year)", isSelected: vm.filterYear == year) {
                        vm.setFilterYear(year)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        }
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

// MARK: - Heart stats panel (top-left)

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

// MARK: - Compact year chip

/// Smaller than the full PillChip — uses labelSmall + tighter padding so the
/// row fits neatly below the top stat panels without dominating the canvas.
private struct BodyMapYearChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.labelSmall)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accent.opacity(0.13) : Color.bgCard.opacity(0.75),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.accent.opacity(0.8) : Color.borderCard,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
