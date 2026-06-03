import Testing
import Foundation
import Core
@testable import BodyMetrics

/// Sprint 8 — body-metric model contract: the decode shape from the backend
/// (`GET /body-metrics`), partial single-metric rows, and the POST payload encoding.
/// The both-or-neither / at-least-one rules live in the view model and the database;
/// here we lock down the wire contract (ADR-017).
struct BodyMetricModelsTests {

    // MARK: - Decode (full row)

    @Test func decodesSnakeCaseDateProvenanceAndNote() throws {
        let json = """
        {
            "id": "bm-1",
            "measured_on": "2026-06-01",
            "weight_kg": 79.1,
            "waist_cm": 89,
            "systolic": 118,
            "diastolic": 76,
            "note": "Down 13 kg.",
            "source": "manual"
        }
        """.data(using: .utf8)!

        let metric = try JSONDecoder.api.decode(BodyMetric.self, from: json)
        #expect(metric.id == "bm-1")
        #expect(metric.weightKg == 79.1)
        #expect(metric.waistCm == 89)
        #expect(metric.systolic == 118)
        #expect(metric.diastolic == 76)
        #expect(metric.note == "Down 13 kg.")
        #expect(metric.source == .manual)

        let comps = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: metric.measuredOn
        )
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 1)
    }

    // MARK: - Decode (partial row — a metric a user logged on its own)

    @Test func decodesWeightOnlyRowWithNullMetrics() throws {
        let json = """
        {
            "id": "bm-2",
            "measured_on": "2026-05-15",
            "weight_kg": 82.0,
            "waist_cm": null,
            "systolic": null,
            "diastolic": null,
            "note": null,
            "source": "healthkit"
        }
        """.data(using: .utf8)!

        let metric = try JSONDecoder.api.decode(BodyMetric.self, from: json)
        #expect(metric.weightKg == 82.0)
        #expect(metric.waistCm == nil)
        #expect(metric.systolic == nil)
        #expect(metric.diastolic == nil)
        #expect(metric.note == nil)
        // Provenance survives the round trip so synced rows can be labelled (Sprints 9–10).
        #expect(metric.source == .healthkit)
    }

    // MARK: - Encode (POST body)

    @Test func payloadEncodesSnakeCaseAndOmittedMetricsAsNull() throws {
        let measured = Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 6, day: 1)
        )!
        let payload = BodyMetricPayload(
            measuredOn: measured,
            weightKg: 80.5,
            waistCm: nil,
            systolic: 120,
            diastolic: 80,
            note: "after fast"
        )

        let data = try JSONEncoder.api.encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["weight_kg"] as? Double == 80.5)
        #expect(object["systolic"] as? Int == 120)
        #expect(object["diastolic"] as? Int == 80)
        #expect(object["note"] as? String == "after fast")
        // Omitted optional metrics use `encodeIfPresent`, so the key is absent (not null).
        #expect(object["waist_cm"] == nil)
        // Date is sent as an ISO-8601 string the backend parses as a date.
        #expect((object["measured_on"] as? String)?.hasPrefix("2026-06-01") == true)
    }
}
