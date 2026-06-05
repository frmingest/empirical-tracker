import BodyMetrics
import Core
import DietEvents
import SwiftUI

/// The Body tab (Sprint 8). Manual weight / waist / blood-pressure logging with three
/// trend charts that share the diet-event correlation overlay (ADR-017). The body's
/// fast-responding signals shown next to the slow-moving labs.
struct BodyMetricsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: BodyMetricsViewModel?
    @State private var isBodyMapPresented = false
    @State private var showAllHistory = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: String(localized: "body.loading"))
                }
            }
            .navigationTitle(String(localized: "tab.body"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fullScreenCover(isPresented: $isBodyMapPresented) {
                BodyMapView()
            }
            .task {
                if viewModel == nil {
                    viewModel = BodyMetricsViewModel(
                        repo: env.bodyMetrics,
                        dietEventsRepo: env.dietEvents
                    )
                    await viewModel?.load()
                }
                // Top up from Apple Health and arm background observation (Sprint 9).
                await env.healthSyncState.refreshOnAppear()
                // Resolve Withings Cloud status and top up if connected (Sprint 10).
                await env.withingsCloudState.refreshOnAppear()
            }
            .sheet(isPresented: Binding(
                get: { viewModel?.isFormPresented ?? false },
                set: { viewModel?.isFormPresented = $0 }
            )) {
                if let vm = viewModel {
                    LogBodyMetricSheet(viewModel: vm)
                }
            }
            .alert(
                String(localized: "body.error.title"),
                isPresented: Binding(
                    get: { viewModel?.errorMessage != nil },
                    set: { if !$0 { viewModel?.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(viewModel?.errorMessage ?? "")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isBodyMapPresented = true
            } label: {
                Image(systemName: "figure.stand.line.dotted")
                    .accessibilityLabel("Body Map")
            }
            .foregroundStyle(Color.accent)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel?.beginAdd()
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel(String(localized: "body.add"))
            }
            .foregroundStyle(Color.accent)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: BodyMetricsViewModel) -> some View {
        if vm.isLoading && !vm.hasMetrics {
            LoadingView(message: String(localized: "body.loading"))
        } else {
            List {
                // Apple Health connect / sync card (Sprint 9) — shown above the data
                // so a first-run user can import before logging anything by hand.
                HealthSyncSection(state: env.healthSyncState)
                // Withings Cloud connect / sync card (Sprint 10) — Path B, self-hides
                // until the backend exposes the Withings endpoints.
                WithingsCloudSection(state: env.withingsCloudState)

                if vm.hasMetrics {
                    chartsSection(vm)
                    historySection(vm)
                } else {
                    emptySection(vm)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func emptySection(_ vm: BodyMetricsViewModel) -> some View {
        Section {
            VStack(spacing: 20) {
                EmptyStateView(
                    icon: "figure.walk",
                    title: String(localized: "body.empty.title"),
                    message: String(localized: "body.empty.message")
                )
                Button {
                    vm.beginAdd()
                } label: {
                    Label(String(localized: "body.add"), systemImage: "plus")
                        .font(.headlineSmall)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    private static let historyPageSize = 100

    private func historySection(_ vm: BodyMetricsViewModel) -> some View {
        let all = vm.history
        let visible = showAllHistory ? all : Array(all.prefix(Self.historyPageSize))
        let hasMore = !showAllHistory && all.count > Self.historyPageSize

        return Section {
            ForEach(visible) { metric in
                BodyMetricRow(metric: metric)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(metric) }
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
            }
            if hasMore {
                Button {
                    showAllHistory = true
                } label: {
                    Text("Show all \(all.count) entries")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            Text(String(localized: "body.history.title"))
        } footer: {
            disclaimerFooter
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private func chartsSection(_ vm: BodyMetricsViewModel) -> some View {
        if !vm.weightPoints.isEmpty {
            Section {
                BodyMetricChart(
                    title: String(localized: "body.chart.weight"),
                    unit: String(localized: "body.unit.kg"),
                    series: [.init(
                        id: "weight",
                        label: String(localized: "body.chart.weight"),
                        color: .accent,
                        points: vm.weightPoints
                    )],
                    events: vm.overlappingEvents
                )
                .chartRowStyle()
            }
        }

        if !vm.waistPoints.isEmpty {
            Section {
                BodyMetricChart(
                    title: String(localized: "body.chart.waist"),
                    unit: String(localized: "body.unit.cm"),
                    series: [.init(
                        id: "waist",
                        label: String(localized: "body.chart.waist"),
                        color: .inRange,
                        points: vm.waistPoints
                    )],
                    events: vm.overlappingEvents
                )
                .chartRowStyle()
            }
        }

        if !vm.systolicPoints.isEmpty {
            Section {
                BodyMetricChart(
                    title: String(localized: "body.chart.bp"),
                    unit: String(localized: "body.unit.mmhg"),
                    series: [
                        .init(id: "sys", label: String(localized: "body.metric.systolic"),
                              color: .outRange, points: vm.systolicPoints),
                        .init(id: "dia", label: String(localized: "body.metric.diastolic"),
                              color: .accent, points: vm.diastolicPoints),
                    ],
                    guidelines: [.init(value: 120), .init(value: 80)],
                    events: vm.overlappingEvents
                )
                .chartRowStyle()
            }
        }
    }

    private var disclaimerFooter: some View {
        Label {
            Text(String(localized: "body.disclaimer"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accent)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart row styling

private extension View {
    /// Charts sit edge-to-edge on a card background inside the grouped list.
    func chartRowStyle() -> some View {
        self
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.bgCard)
    }
}

// MARK: - History row

private struct BodyMetricRow: View {
    let metric: BodyMetric

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Text(summaryText)
                    .font(.numericSmall)
                    .foregroundStyle(Color.textSecondary)
                if let note = metric.note, !note.isEmpty {
                    Text(note)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let sourceLabel = metric.source.badgeLabel {
                Text(sourceLabel)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.bgElevated, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dateText). \(summaryText)")
    }

    private var dateText: String {
        metric.measuredOn.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var summaryText: String {
        var parts: [String] = []
        if let w = metric.weightKg {
            parts.append("\(format(w)) \(String(localized: "body.unit.kg"))")
        }
        if let waist = metric.waistCm {
            parts.append("\(format(waist)) \(String(localized: "body.unit.cm"))")
        }
        if let sys = metric.systolic, let dia = metric.diastolic {
            parts.append("\(sys)/\(dia) \(String(localized: "body.unit.mmhg"))")
        }
        return parts.joined(separator: " · ")
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

// MARK: - Source provenance (view layer)

private extension BodyMetric.Source {
    /// A small badge for synced rows (Sprints 9–10). Manual entries carry no badge.
    var badgeLabel: String? {
        switch self {
        case .manual:    return nil
        case .healthkit: return String(localized: "body.source.healthkit")
        case .withings:  return String(localized: "body.source.withings")
        }
    }
}

// MARK: - Preview

#Preview {
    let env: AppEnvironment = {
        let e = AppEnvironment.preview()
        e.bodyMetrics.metrics = MockData.bodyMetrics
        e.dietEvents.events = MockData.dietEvents
        return e
    }()
    BodyMetricsView()
        .environment(env)
}
