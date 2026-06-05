import BodyMetrics
import Core
import DietEvents
import Foundation
import Observation

/// View model for `BodyMetricsView` (Sprint 8).
/// Owns the log-form draft and validation; delegates persistence to
/// `BodyMetricsRepository` and reads diet events for the shared chart overlay.
/// Validation mirrors ADR-017 and the backend `BodyMetricIn` validator so the
/// user gets a friendly inline message instead of a 422.
@MainActor
@Observable
final class BodyMetricsViewModel {

    // MARK: - List state

    var isLoading = false
    var errorMessage: String?

    // MARK: - Form sheet

    var isFormPresented = false

    // MARK: - Form draft

    var formDate: Date = .now
    var formWeight = ""
    var formWaist = ""
    var formSystolic = ""
    var formDiastolic = ""
    var formNote = ""

    // MARK: - Dependencies

    private let repo: BodyMetricsRepository
    private let dietEventsRepo: DietEventsRepository

    init(repo: BodyMetricsRepository, dietEventsRepo: DietEventsRepository) {
        self.repo = repo
        self.dietEventsRepo = dietEventsRepo
    }

    // MARK: - Passthrough (observed via the repository)

    var metrics: [BodyMetric] { repo.metrics }
    var hasMetrics: Bool { !repo.metrics.isEmpty }

    /// Newest-first for the log/history table (the repo keeps them oldest-first for charts).
    var history: [BodyMetric] { repo.metrics.sorted { $0.measuredOn > $1.measuredOn } }

    // MARK: - Chart series (each metric skips the rows where it is null — ADR-017 §3)

    var weightPoints: [BodyMetricChart.DataPoint] {
        repo.metrics.compactMap { m in m.weightKg.map { .init(date: m.measuredOn, value: $0) } }
    }
    var waistPoints: [BodyMetricChart.DataPoint] {
        repo.metrics.compactMap { m in m.waistCm.map { .init(date: m.measuredOn, value: $0) } }
    }
    var systolicPoints: [BodyMetricChart.DataPoint] {
        repo.metrics.compactMap { m in m.systolic.map { .init(date: m.measuredOn, value: Double($0)) } }
    }
    var diastolicPoints: [BodyMetricChart.DataPoint] {
        repo.metrics.compactMap { m in m.diastolic.map { .init(date: m.measuredOn, value: Double($0)) } }
    }

    struct BPReading {
        let systolic: Int
        let diastolic: Int
    }

    var latestBP: BPReading? {
        repo.metrics
            .sorted { $0.measuredOn > $1.measuredOn }
            .first { $0.systolic != nil && $0.diastolic != nil }
            .flatMap { m in
                guard let s = m.systolic, let d = m.diastolic else { return nil }
                return BPReading(systolic: s, diastolic: d)
            }
    }

    var averageBP: BPReading? {
        let readings = repo.metrics.compactMap { m -> BPReading? in
            guard let s = m.systolic, let d = m.diastolic else { return nil }
            return BPReading(systolic: s, diastolic: d)
        }
        guard !readings.isEmpty else { return nil }
        let avgSys = readings.map(\.systolic).reduce(0, +) / readings.count
        let avgDia = readings.map(\.diastolic).reduce(0, +) / readings.count
        return BPReading(systolic: avgSys, diastolic: avgDia)
    }

    /// Diet events intersecting the full body-metrics window, for the chart overlay.
    var overlappingEvents: [DietEvent] {
        let dates = repo.metrics.map(\.measuredOn)
        guard let first = dates.min(), let last = dates.max() else { return [] }
        return dietEventsRepo.events(overlapping: first, end: last)
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        errorMessage = nil
        await repo.load()
        // Diet events power the correlation overlay; only fetch if no one else has.
        if dietEventsRepo.events.isEmpty { await dietEventsRepo.load() }
        if let err = repo.error { errorMessage = err.localizedDescription }
        isLoading = false
    }

    // MARK: - Add entry point

    func beginAdd() {
        resetForm()
        isFormPresented = true
    }

    // MARK: - Parsed draft values

    private var weightValue: Double? { Self.parseDouble(formWeight) }
    private var waistValue: Double? { Self.parseDouble(formWaist) }
    private var systolicValue: Int? { Self.parseInt(formSystolic) }
    private var diastolicValue: Int? { Self.parseInt(formDiastolic) }

    private var hasWeight: Bool { !formWeight.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasWaist: Bool { !formWaist.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasSystolic: Bool { !formSystolic.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasDiastolic: Bool { !formDiastolic.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Validation

    /// At least one metric must be entered for the Add button to enable.
    private var hasAnyMetric: Bool { hasWeight || hasWaist || hasSystolic }

    /// Red inline error for a *conflicting* entry (only surfaced once the user has
    /// typed the relevant field). The pure "nothing entered yet" case is covered by
    /// the disabled button and the neutral hint, not an error.
    var formError: String? {
        // bp_pair — both-or-neither
        if hasSystolic != hasDiastolic {
            return String(localized: "body.error.bp_pair")
        }
        if hasWeight, weightValue == nil || (weightValue ?? 0) <= 0 {
            return String(localized: "body.error.weight_range")
        }
        if hasWaist, waistValue == nil || (waistValue ?? 0) <= 0 {
            return String(localized: "body.error.waist_range")
        }
        if hasSystolic {
            guard let s = systolicValue, (40...300).contains(s) else {
                return String(localized: "body.error.systolic_range")
            }
            guard let d = diastolicValue, (20...200).contains(d) else {
                return String(localized: "body.error.diastolic_range")
            }
        }
        return nil
    }

    var isFormValid: Bool { hasAnyMetric && formError == nil }

    // MARK: - Persistence

    func submitForm() async {
        guard isFormValid else { return }
        errorMessage = nil
        let trimmedNote = formNote.trimmingCharacters(in: .whitespaces)
        let payload = BodyMetricPayload(
            measuredOn: Calendar.current.startOfDay(for: formDate),
            weightKg: weightValue,
            waistCm: waistValue,
            systolic: systolicValue,
            diastolic: diastolicValue,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        do {
            try await repo.create(payload)
            resetForm()
            isFormPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ metric: BodyMetric) async {
        do {
            try await repo.delete(id: metric.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetForm() {
        formDate = .now
        formWeight = ""
        formWaist = ""
        formSystolic = ""
        formDiastolic = ""
        formNote = ""
    }

    // MARK: - Parsing (tolerates Norwegian decimal commas)

    private static func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private static func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }
}
