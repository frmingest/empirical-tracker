import Testing
import Foundation
import Core
@testable import Biomarkers

/// Unit tests for the Sprint 3 marker-signal, assessment, and clinical-target logic.
struct MarkerSignalsTests {

    // MARK: - Fixtures

    private func bounded(
        nameNo: String = "Testmarkør",
        unit: String? = "mmol/L",
        low: Double? = 4,
        high: Double? = 6,
        values: [Double],
        inRange: [Bool?]? = nil
    ) -> BiomarkerWithSeries {
        let info = BiomarkerInfo(
            id: nameNo,
            nameNo: nameNo,
            unit: unit,
            refRangeRaw: "\(low ?? 0) - \(high ?? 0)",
            refLow: low,
            refHigh: high,
            refType: .bounded
        )
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        let points = values.enumerated().map { idx, v in
            ResultPoint(
                testedAt: start.addingTimeInterval(Double(idx) * 86_400 * 30),
                value: v,
                inRange: inRange?[idx] ?? (v >= (low ?? -.infinity) && v <= (high ?? .infinity))
            )
        }
        return BiomarkerWithSeries(biomarker: info, series: points)
    }

    // MARK: - Assessment

    @Test func outOfRangeLatestIsOutOfRange() {
        let marker = bounded(values: [5.0, 7.5]) // 7.5 > high 6 → out of range
        #expect(MarkerSignals.assessment(for: marker) == .outOfRange)
    }

    @Test func steadyInRangeIsInRange() {
        let marker = bounded(values: [5.0, 5.1, 5.0])
        #expect(MarkerSignals.assessment(for: marker) == .inRange)
    }

    @Test func noReferenceRangeIsUnknown() {
        let info = BiomarkerInfo(
            id: "x", nameNo: "X", unit: nil, refRangeRaw: "", refType: .none
        )
        let marker = BiomarkerWithSeries(
            biomarker: info,
            series: [ResultPoint(testedAt: .now, value: 1, inRange: nil)]
        )
        #expect(MarkerSignals.assessment(for: marker) == .unknown)
    }

    // MARK: - Signals

    @Test func largeStepProducesWatchSignal() {
        // 5.0 → 8.0 is a 60% increase: large step. 8.0 is also out of range.
        let marker = bounded(values: [5.0, 8.0])
        let signals = MarkerSignals.signals(for: marker)
        #expect(signals.contains { $0.kind == .largeStep })
        #expect(signals.contains { $0.kind == .outOfRange })
    }

    @Test func notableButNotLargeChange() {
        // 4.0 → 5.2 is a 30% increase, still in range [4,6]: notable, not large.
        let marker = bounded(values: [4.0, 5.2])
        let signals = MarkerSignals.signals(for: marker)
        #expect(signals.contains { $0.kind == .notableChange })
        #expect(!signals.contains { $0.kind == .largeStep })
    }

    @Test func approachingUpperBoundIsWatch() {
        // In range but rising to 5.9 (range [4,6], near-bound window = 0.2): watch.
        let marker = bounded(values: [5.0, 5.9])
        let signals = MarkerSignals.signals(for: marker)
        #expect(signals.contains { $0.kind == .trendingTowardBound })
        #expect(MarkerSignals.assessment(for: marker) == .watch)
    }

    // MARK: - Clinical targets

    @Test func ldlTargetInMmol() {
        let info = BiomarkerInfo(
            id: "ldl", nameNo: "LDL-kolesterol", nameEn: "LDL cholesterol",
            unit: "mmol/L", refRangeRaw: "< 3.0", refHigh: 3.0, refType: .lt
        )
        #expect(info.clinicalTarget?.value == 2.6)
    }

    @Test func totalCholesterolTargetNotConfusedWithLDL() {
        let info = BiomarkerInfo(
            id: "chol", nameNo: "Kolesterol", nameEn: "Cholesterol",
            unit: "mmol/L", refRangeRaw: "3.3 - 6.9", refLow: 3.3, refHigh: 6.9, refType: .bounded
        )
        #expect(info.clinicalTarget?.value == 5.0)
    }

    @Test func noTargetForUnmatchedMarker() {
        let info = BiomarkerInfo(
            id: "na", nameNo: "Natrium", unit: "mmol/L", refRangeRaw: "137 - 145",
            refLow: 137, refHigh: 145, refType: .bounded
        )
        #expect(info.clinicalTarget == nil)
    }

    @Test func wrongUnitSuppressesLipidTarget() {
        let info = BiomarkerInfo(
            id: "ldl-mg", nameNo: "LDL-kolesterol", unit: "mg/dL",
            refRangeRaw: "< 116", refHigh: 116, refType: .lt
        )
        #expect(info.clinicalTarget == nil)
    }
}
