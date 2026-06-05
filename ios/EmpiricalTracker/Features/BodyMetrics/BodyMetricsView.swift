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
    @AppStorage("body.heightCm") private var heightCm: Double = 0
    @State private var heightInput = ""
    @State private var isEditingHeight = false

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
                statsCardsSection(vm)

                if vm.hasMetrics {
                    chartsSection(vm)
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

    // MARK: - Stats cards

    @ViewBuilder
    private func statsCardsSection(_ vm: BodyMetricsViewModel) -> some View {
        let latestWeight = vm.weightPoints.last?.value
        let latestWaist  = vm.waistPoints.last?.value
        let bmi: Double? = {
            guard let w = latestWeight, heightCm > 0 else { return nil }
            let hm = heightCm / 100.0
            return w / (hm * hm)
        }()

        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "Weight",
                    value: latestWeight.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? "–",
                    icon: "scalemass",
                    color: .accent
                )
                StatCard(
                    title: "Waist",
                    value: latestWaist.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) cm" } ?? "–",
                    icon: "ruler",
                    color: .inRange
                )
                HeightStatCard(
                    heightCm: $heightCm,
                    heightInput: $heightInput,
                    isEditing: $isEditingHeight
                )
                StatCard(
                    title: "BMI",
                    value: bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                    icon: "chart.bar.fill",
                    color: bmiColor(bmi),
                    subtitle: bmiCategory(bmi)
                )
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func bmiColor(_ bmi: Double?) -> Color {
        guard let bmi else { return .textMuted }
        switch bmi {
        case ..<18.5: return .outRange
        case 18.5..<25: return .inRange
        case 25..<30: return .outRange
        default: return .outRange
        }
    }

    private func bmiCategory(_ bmi: Double?) -> String? {
        guard let bmi else { return nil }
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
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

// MARK: - Stat cards

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.labelSmall)
                    .foregroundStyle(color)
                Text(title)
                    .font(.labelSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(value)
                .font(.numericMedium)
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.bodySmall)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HeightStatCard: View {
    @Binding var heightCm: Double
    @Binding var heightInput: String
    @Binding var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.and.down")
                    .font(.labelSmall)
                    .foregroundStyle(Color.accent)
                Text("Height")
                    .font(.labelSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            if isEditing {
                HStack(spacing: 4) {
                    TextField("cm", text: $heightInput)
                        .font(.numericMedium)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                    Button {
                        if let v = Double(heightInput.replacingOccurrences(of: ",", with: ".")), v > 0 {
                            heightCm = v
                        }
                        isEditing = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accent)
                    }
                }
            } else {
                Button {
                    heightInput = heightCm > 0 ? String(format: "%.0f", heightCm) : ""
                    isEditing = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(heightCm > 0 ? String(format: "%.0f cm", heightCm) : "Tap to set")
                            .font(.numericMedium)
                            .foregroundStyle(heightCm > 0 ? Color.textPrimary : Color.textMuted)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
