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
        // The bottom strip of this view sits behind the floating tab bar — the
        // NavigationStack doesn't honour the safe-area inset RootView reserves
        // for it, so anything anchored there gets hidden (this is why the old
        // colour legend was moved to the top in PR #128). The filter lives at
        // the top, beside the toolbar, for the same reason.
        return VStack(spacing: 0) {
            // ── Single "latest results" filter — top-anchored, always visible ──
            HStack {
                PillChip("Latest results", isSelected: vm.showLatestOnly) {
                    vm.toggleLatestOnly()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)

            // ── Silhouette canvas (takes all remaining vertical space) ──────
            ZStack(alignment: .top) {
                BodyMapCanvas(
                    regions: vm.regions,
                    silhouetteOpacity: 0.18,
                    bottomReserve: 0
                ) { region in
                    selectedRegion = region
                }

                // Stat panels overlaid at the top of the canvas only
                HStack(alignment: .top) {
                    HeartStatsPanel(
                        metrics: env.bodyMetrics.metrics,
                        lastSyncDate: env.healthSyncState.lastSyncDate,
                        isSyncing: env.healthSyncState.isSyncing
                    )
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
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Heart stats panel (top-left)

/// Compact panel showing latest resting heart rate and HRV from Apple Watch.
/// Tapping the card opens a plain-language explanation of both metrics.
struct HeartStatsPanel: View {
    let metrics: [BodyMetric]
    /// Freshness of the HealthKit-sourced data this card shows. Lives here — on
    /// the card it actually describes — instead of as an orphan label adrift in
    /// the bottom strip.
    var lastSyncDate: Date? = nil
    var isSyncing: Bool = false

    @State private var showInfo = false

    private var sorted: [BodyMetric] { metrics.sorted { $0.measuredOn > $1.measuredOn } }

    private var latestRHR: Int? { sorted.first { $0.restingHeartRateBpm != nil }?.restingHeartRateBpm }
    private var latestHRV: Double? { sorted.first { $0.hrvMs != nil }?.hrvMs }

    private func hrColor(_ bpm: Int?) -> Color {
        guard let bpm else { return .textMuted }
        return (60...100).contains(bpm) ? .inRange : .outRange
    }

    var body: some View {
        Button { showInfo = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    HeartRow(
                        icon: "heart.fill",
                        label: "Resting HR",
                        value: latestRHR.map { "\($0) BPM" } ?? "--",
                        color: hrColor(latestRHR)
                    )
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                }
                HeartRow(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: latestHRV.map { String(format: "%.0f ms", $0) } ?? "--",
                    color: .accent
                )

                if isSyncing || lastSyncDate != nil {
                    SyncFreshnessLabel(date: lastSyncDate, isSyncing: isSyncing)
                        .padding(.top, 1)
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
            .frame(maxWidth: 148)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showInfo) {
            HeartMetricsInfoSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
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

// MARK: - Heart metrics info sheet

private struct HeartMetricsInfoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.outRange)
                    Text("Resting Heart Rate")
                        .font(.headlineMedium)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("This is how many times your heart beats per minute when you're completely at rest — sitting still or lying down. A lower number generally means your heart is working more efficiently. Most healthy adults fall between **60 and 100 BPM**. Athletes often run lower. A high resting HR over time can be a sign of stress, poor sleep, or that your body is fighting something off.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Color.accent)
                    Text("Heart Rate Variability (HRV)")
                        .font(.headlineMedium)
                        .foregroundStyle(Color.textPrimary)
                }
                Text("HRV measures the tiny variation in time between each heartbeat. Counterintuitively, **more variation is better** — it means your nervous system is flexible and recovering well. A higher HRV typically signals good sleep, low stress, and solid fitness. A low or falling HRV often appears before you feel run-down. HRV is highly personal, so trends over time matter more than any single number.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .background(Color.bgBase)
    }
}

// MARK: - Sync freshness (replaces the orphan "Synced X ago" label)

/// Compact data-freshness indicator that lives inside the HR/HRV card. Calm grey
/// when recent, amber "Stale" past a day so it only draws the eye when it should.
private struct SyncFreshnessLabel: View {
    let date: Date?
    let isSyncing: Bool

    private var isStale: Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) > 24 * 3600
    }

    private var text: String {
        if isSyncing { return "Syncing…" }
        guard let date else { return "Not synced" }
        let relative = date.formatted(.relative(presentation: .named))
        return isStale ? "Stale · \(relative)" : "Synced \(relative)"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(.rotate, isActive: isSyncing)
            Text(text)
                .font(.labelSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isStale ? Color.orange : Color.textMuted)
        .accessibilityLabel(isSyncing ? "Syncing health data" : "Health data \(text)")
    }
}
