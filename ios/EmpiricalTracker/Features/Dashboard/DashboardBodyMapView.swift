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
    /// Spotlight selection from the status-summary row, identified by
    /// `Assessment.legendOrder`. `nil` = show every pin at full strength.
    @State private var spotlightOrder: Int?
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
        // Layout philosophy (the reason this finally stops getting clipped):
        // the contested bottom strip now carries ONLY the year filter. The colour
        // key became a live status-summary row anchored to the TOP safe area — the
        // one place the nav bar guarantees space — and data-freshness moved onto
        // the card whose data it describes. Nothing new competes for the home-
        // indicator band, so there is nothing left to squeeze off-screen.
        let hasYearFilter = vm.availableYears.count > 1

        return VStack(spacing: 0) {
            // ── Live status summary (replaces the old colour legend) ─────────
            BodyMapStatusSummary(
                regions: vm.regions,
                spotlightOrder: $spotlightOrder
            )
            .padding(.top, 6)
            .padding(.bottom, 2)

            // ── Silhouette canvas (takes all remaining vertical space) ──────
            ZStack(alignment: .top) {
                BodyMapCanvas(
                    regions: vm.regions,
                    silhouetteOpacity: 0.18,
                    bottomReserve: hasYearFilter ? 0 : 32,
                    highlightedAssessment: spotlightOrder.flatMap(assessment(forOrder:))
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

            // ── Year filter — now the sole occupant of the bottom strip ──────
            if hasYearFilter {
                yearFilterRow(vm)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            } else {
                Spacer().frame(height: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }

    /// Maps a stored `legendOrder` back to its `Assessment` for the canvas.
    private func assessment(forOrder order: Int) -> MarkerSignals.Assessment? {
        MarkerSignals.Assessment.legendOrdered.first { $0.legendOrder == order }
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

// MARK: - Status summary (replaces the old colour legend)

/// A live, top-anchored summary of how many body regions sit in each status.
///
/// This is the redesign of the old passive colour legend. Instead of a static
/// "what the colours mean" capsule jammed into the crowded bottom strip, it is a
/// genuinely useful headline — "12 in range, 1 out of range" — that teaches the
/// colour code as a side effect (dot + icon + word per status). Each chip is a
/// spotlight toggle: tap it to fade every pin on the body except that status.
/// A trailing info button opens the full key with plain-language definitions, so
/// nothing reference-only needs to live permanently on screen.
struct BodyMapStatusSummary: View {
    let regions: [BodyRegion]
    @Binding var spotlightOrder: Int?

    @State private var isKeyPresented = false

    /// Only statuses that actually occur are shown, so a healthy user sees a calm
    /// single chip rather than four — but a present status is never hidden.
    private var visibleStatuses: [MarkerSignals.Assessment] {
        MarkerSignals.Assessment.legendOrdered.filter { count(for: $0) > 0 }
    }

    private func count(for assessment: MarkerSignals.Assessment) -> Int {
        regions.filter { $0.worstAssessment.legendOrder == assessment.legendOrder }.count
    }

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(visibleStatuses, id: \.legendOrder) { status in
                        StatusCountChip(
                            assessment: status,
                            count: count(for: status),
                            isSelected: spotlightOrder == status.legendOrder,
                            isDimmed: spotlightOrder != nil && spotlightOrder != status.legendOrder
                        ) {
                            toggle(status)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)

            Button { isKeyPresented = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("What the colours mean")
            .padding(.trailing, 12)
            .popover(isPresented: $isKeyPresented) {
                BodyMapKeySheet()
                    .presentationCompactAdaptation(.popover)
            }
        }
        .animation(.snappy(duration: 0.22), value: spotlightOrder)
    }

    private func toggle(_ status: MarkerSignals.Assessment) {
        spotlightOrder = (spotlightOrder == status.legendOrder) ? nil : status.legendOrder
    }
}

private struct StatusCountChip: View {
    let assessment: MarkerSignals.Assessment
    let count: Int
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: assessment.legendIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(assessment.pinColor)
                Text("\(count)")
                    .font(.headlineSmall)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(assessment.legendLabel)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? assessment.pinColor.opacity(0.15) : Color.bgCard.opacity(0.7),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? assessment.pinColor.opacity(0.85) : Color.borderSubtle.opacity(0.6),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            )
            .opacity(isDimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(assessment.legendLabel)")
        .accessibilityHint("Tap to highlight these on the body")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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

// MARK: - On-demand status key

/// The full colour key with plain-language meanings, shown only when the user
/// taps the info button — so reference material never occupies permanent space.
private struct BodyMapKeySheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What the colours mean")
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)

            ForEach(MarkerSignals.Assessment.legendOrdered, id: \.legendOrder) { status in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: status.legendIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(status.pinColor)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.legendLabel)
                            .font(.headlineSmall)
                            .foregroundStyle(Color.textPrimary)
                        Text(status.legendDescription)
                            .font(.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}
