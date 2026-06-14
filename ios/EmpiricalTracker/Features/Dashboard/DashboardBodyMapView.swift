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
                    LoadingView(message: String(localized: "dashboard.loading"))
                } else {
                    bodyCanvas(vm)
                }
            } else {
                LoadingView(message: String(localized: "dashboard.loading"))
            }
        }
        .task {
            if viewModel == nil {
                viewModel = BodyMapViewModel(biomarkersRepo: env.biomarkers)
            }
            // The silhouette's HR/HRV and weight panels read env.bodyMetrics /
            // env.activityMetrics / env.healthSyncState — but those were only
            // primed by the Trends tab. Prime them here too so the data is
            // present on first launch without a detour through Trends.
            async let bm: () = env.bodyMetrics.load()
            async let am: () = env.activityMetrics.load()
            await viewModel?.load()
            _ = await (bm, am)
            // Top up from Apple Health + arm background observation. This is the
            // same call the Trends tab uses; it self-guards on connection state
            // and a 5-minute window, so visiting both tabs won't double-sync.
            await env.healthSyncState.refreshOnAppear()
        }
        .navigationDestination(item: $selectedRegion) { region in
            OrganDetailView(region: region) { marker in
                onSelectMarker(marker)
            }
        }
    }

    // MARK: - Canvas

    private func bodyCanvas(_ vm: BodyMapViewModel) -> some View {
        // Redesign (Option A): the two floating glass panels that used to sit
        // *over* the silhouette's head/chest are gone. Their numbers now live in a
        // single slim "vitals bar" anchored above the figure, so the canvas itself
        // is free of overlays and the markers have room to breathe. The "Latest
        // results" filter moved into the navigation toolbar (.principal) — it only
        // appears in body-map mode because this view is only built in that mode.
        return VStack(spacing: 0) {
            VitalsSummaryBar(
                metrics: env.bodyMetrics.metrics,
                heightCm: heightCm > 0 ? heightCm : nil,
                lastSyncDate: env.healthSyncState.lastSyncDate,
                isSyncing: env.healthSyncState.isSyncing
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)

            // ── Silhouette canvas — no overlays, takes all remaining space ──
            BodyMapCanvas(
                regions: vm.regions,
                biologicalSex: env.userProfile.biologicalSex,
                silhouetteOpacity: 0.18,
                bottomReserve: 0
            ) { region in
                selectedRegion = vm.detailRegion(for: region.id) ?? region
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Results", selection: Binding(
                    get: { vm.showLatestOnly },
                    set: { wantLatest in
                        if wantLatest != vm.showLatestOnly { vm.toggleLatestOnly() }
                    }
                )) {
                    Text("Latest").tag(true)
                    Text("All").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                .accessibilityLabel("Results shown")
            }
        }
    }
}

// MARK: - Vitals summary bar

/// A single slim, full-width bar that replaces the two floating stat cards that
/// used to overlay the silhouette. Heart metrics (tappable for an explanation),
/// body metrics and the sync-freshness indicator all sit on one scannable line,
/// so nothing covers the figure. The row scrolls horizontally on narrow devices
/// rather than dropping any metric.
struct VitalsSummaryBar: View {
    let metrics: [BodyMetric]
    let heightCm: Double?
    var lastSyncDate: Date? = nil
    var isSyncing: Bool = false

    @State private var showHeartInfo = false

    private var sorted: [BodyMetric] { metrics.sorted { $0.measuredOn > $1.measuredOn } }
    private var latestRHR: Int? { sorted.first { $0.restingHeartRateBpm != nil }?.restingHeartRateBpm }
    private var latestHRV: Double? { sorted.first { $0.hrvMs != nil }?.hrvMs }
    private var latestWeight: Double? { sorted.first { $0.weightKg != nil }?.weightKg }
    private var latestWaist: Double? { sorted.first { $0.waistCm != nil }?.waistCm }

    private var bmiText: String {
        guard let h = heightCm.map({ $0 / 100.0 }), h > 0, let kg = latestWeight else { return "--" }
        return String(format: "%.1f", kg / (h * h))
    }

    private func hrColor(_ bpm: Int?) -> Color {
        guard let bpm else { return .textMuted }
        return (60...100).contains(bpm) ? .inRange : .outRange
    }

    var body: some View {
        CardView(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                // Row 1 — body metrics: height, weight, waist, BMI.
                HStack(spacing: 14) {
                    VitalCell(icon: "ruler", label: "Height",
                              value: heightCm.map { String(format: "%.0f cm", $0) } ?? "--")
                    VitalCell(icon: "scalemass", label: "Weight",
                              value: latestWeight.map { String(format: "%.1f kg", $0) } ?? "--")
                    VitalCell(icon: "circle.dashed", label: "Waist",
                              value: latestWaist.map { String(format: "%.0f cm", $0) } ?? "--")
                    VitalCell(icon: "figure.stand", label: "BMI", value: bmiText)

                    Spacer(minLength: 0)
                }

                // Row 2 — heart group (tappable for the plain-language sheet) + sync freshness.
                HStack(spacing: 14) {
                    Button { showHeartInfo = true } label: {
                        HStack(spacing: 14) {
                            VitalCell(
                                icon: "heart.fill",
                                label: "Resting HR",
                                value: latestRHR.map { "\($0) BPM" } ?? "--",
                                iconColor: hrColor(latestRHR)
                            )
                            VitalCell(
                                icon: "waveform.path.ecg",
                                label: "HRV",
                                value: latestHRV.map { String(format: "%.0f ms", $0) } ?? "--",
                                iconColor: .accent
                            )
                            Image(systemName: "info.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)

                    if isSyncing || lastSyncDate != nil {
                        cellDivider
                        SyncFreshnessLabel(date: lastSyncDate, isSyncing: isSyncing)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .sheet(isPresented: $showHeartInfo) {
            HeartMetricsInfoSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var cellDivider: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.borderCard)
            .frame(width: 1, height: 26)
            .accessibilityHidden(true)
    }
}

/// One icon + label + value column used inside the vitals bar. Colour is always
/// paired with an icon and the value text, never the sole signal (ADR-006).
private struct VitalCell: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .accent

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 15)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
                Text(value)
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
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

// MARK: - Sync freshness

/// Compact data-freshness indicator. Calm grey when recent, amber "Stale" past a
/// day so it only draws the eye when it should.
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
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(isSyncing ? "Syncing health data" : "Health data \(text)")
    }
}
