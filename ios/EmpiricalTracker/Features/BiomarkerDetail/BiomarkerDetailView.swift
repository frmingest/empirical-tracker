import Biomarkers
import Core
import DietEvents
import SwiftUI

/// Marker detail — the Sprint 3 drill-down pushed from a dashboard card.
/// Full trend chart (reference band, clinical target, diet-event overlay),
/// trend signals, confounder note, and manual result entry.
struct BiomarkerDetailView: View {
    @Environment(AppEnvironment.self) private var env

    /// Snapshot used for the initial render and as a fallback.
    let initialMarker: BiomarkerWithSeries

    @State private var viewModel: BiomarkerDetailViewModel?

    /// Read the marker live from the repository so the chart updates after a
    /// manual result is added; fall back to the snapshot we were pushed with.
    private var marker: BiomarkerWithSeries {
        env.biomarkers.results.first { $0.id == initialMarker.id } ?? initialMarker
    }

    private var info: BiomarkerInfo { marker.biomarker }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                chartCard
                if !marker.series.isEmpty {
                    DietEventCorrelationDisclaimer()
                        .padding(.horizontal, 16)
                }
                signalsSection
                confounderNote
            }
            .padding(.vertical, 16)
        }
        .background(Color.bgBase)
        .navigationTitle(info.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task {
            if viewModel == nil {
                viewModel = BiomarkerDetailViewModel(
                    biomarkersRepo: env.biomarkers,
                    dietEventsRepo: env.dietEvents
                )
            }
            await viewModel?.loadOverlayIfNeeded()
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.isManualEntryPresented ?? false },
            set: { viewModel?.isManualEntryPresented = $0 }
        )) {
            if let vm = viewModel {
                ManualResultSheet(marker: marker, viewModel: vm)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nameEn = info.nameEn, nameEn != info.nameNo {
                Text(info.nameNo)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let latest = marker.latestResult {
                    Text(formattedValue(latest.value))
                        .font(.numericLarge)
                        .foregroundStyle(Color.textPrimary)
                    if let unit = info.unit {
                        Text(unit)
                            .font(.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Text("—")
                        .font(.numericLarge)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                StatusBadgeView(status: badgeStatus)
            }

            Text(referenceText)
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Chart

    private var chartCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trend")
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textSecondary)

                if marker.series.isEmpty {
                    EmptyStateView(
                        icon: "chart.xyaxis.line",
                        title: "No measurements yet",
                        message: "Add a manual result to start a trend."
                    )
                    .frame(height: 200)
                } else {
                    BiomarkerTrendChart(
                        marker: marker,
                        dietEvents: overlappingEvents,
                        isInteractive: true
                    )
                    .frame(height: 260)
                    legend
                    if marker.series.count > 1 {
                        Label("Tap a point to see its exact value and date.", systemImage: "hand.tap")
                            .font(.labelMedium)
                            .foregroundStyle(Color.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: .inRange, label: "Reference range")
            if info.clinicalTarget != nil {
                legendItem(color: .accent, label: "Optimal target")
            }
        }
        .font(.labelMedium)
        .foregroundStyle(Color.textMuted)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color.opacity(0.5))
                .frame(width: 16, height: 3)
            Text(label)
        }
    }

    // MARK: - Signals

    @ViewBuilder
    private var signalsSection: some View {
        let signals = MarkerSignals.signals(for: marker)
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signals")
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 16)

                CardView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(signals.enumerated()), id: \.element.id) { index, signal in
                            if index > 0 { Divider().padding(.vertical, 10) }
                            signalRow(signal)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func signalRow(_ signal: MarkerSignals.Signal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: signalIcon(signal.severity))
                .foregroundStyle(signalColor(signal.severity))
                .font(.bodyMedium)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(signal.detail)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.title). \(signal.detail)")
    }

    // MARK: - Confounder note

    @ViewBuilder
    private var confounderNote: some View {
        if let note = confounderText {
            Label {
                Text(note)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Color.accent)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel?.isManualEntryPresented = true
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("Add manual result")
            }
            .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Derived values

    private var overlappingEvents: [DietEvent] {
        viewModel?.overlappingEvents(for: marker) ?? []
    }

    private var badgeStatus: StatusBadgeView.Status {
        switch MarkerSignals.assessment(for: marker) {
        case .inRange:    return .inRange
        case .outOfRange: return .outOfRange
        case .watch:      return .watch
        case .unknown:    return .unknown
        }
    }

    private var referenceText: String {
        if info.refRangeRaw.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No reference range"
        }
        return "Reference: \(info.refRangeRaw)\(info.unit.map { " \($0)" } ?? "")"
    }

    /// Light confounder note for markers whose interpretation has common caveats.
    /// Mirrors the spirit of the web's `markerNotes.ts`.
    private var confounderText: String? {
        let n = info.nameNo.lowercased()
        if n.contains("gfr") {
            return "eGFR is estimated from creatinine and varies with muscle mass, "
                + "hydration, and a recent high-protein meal. Interpret trends, not single values."
        }
        if n.contains("hba1c") {
            return "HbA1c reflects roughly the last 3 months of glucose. Anaemia, recent "
                + "blood loss, and altered red-cell turnover can shift it independently of glucose."
        }
        if n.contains("ferritin") {
            return "Ferritin is an acute-phase reactant — infection or inflammation can raise it, "
                + "masking low iron stores. Read alongside CRP and transferrin."
        }
        return nil
    }

    private func signalIcon(_ severity: MarkerSignals.Signal.Severity) -> String {
        switch severity {
        case .alert: return "exclamationmark.circle.fill"
        case .watch: return "eye.circle.fill"
        case .info:  return "arrow.up.arrow.down.circle.fill"
        }
    }

    private func signalColor(_ severity: MarkerSignals.Signal.Severity) -> Color {
        switch severity {
        case .alert: return .outRange
        case .watch: return .accent
        case .info:  return .textSecondary
        }
    }

    private func formattedValue(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    env.biomarkers.results = MockData.biomarkerSeries
    return NavigationStack {
        BiomarkerDetailView(initialMarker: MockData.biomarkerSeries[0])
            .environment(env)
    }
}
