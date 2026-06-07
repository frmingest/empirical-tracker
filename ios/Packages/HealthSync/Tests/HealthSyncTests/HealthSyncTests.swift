import Testing
import Foundation
import Core
import BodyMetrics
@testable import HealthSync

/// Sprint 9 — the HealthKit-free seams of the Apple Health sync (ADR-022): the
/// client-side dedupe store, the `source: healthkit` payload contract, and the
/// summary maths. The HealthKit queries themselves need a device and are exercised
/// in the manual on-device test plan, not here.
struct HealthSyncTests {

    // MARK: - Dedupe store

    @Test func storeRemembersAndDeduplicatesUUIDs() async {
        let store = SyncedSampleStore(suiteName: "test.healthsync.\(UUID().uuidString)")

        #expect(await store.contains("A") == false)
        await store.insert("A")
        #expect(await store.contains("A") == true)
        #expect(await store.count == 1)

        // Re-inserting the same UUID is idempotent.
        await store.insert("A")
        #expect(await store.count == 1)

        await store.insert("B")
        #expect(await store.count == 2)
    }

    @Test func storePersistsAcrossInstancesAndResets() async {
        let suite = "test.healthsync.\(UUID().uuidString)"
        let first = SyncedSampleStore(suiteName: suite)
        await first.insert("X")

        // A fresh instance over the same suite sees the previously synced UUID,
        // so a relaunch never re-uploads it.
        let second = SyncedSampleStore(suiteName: suite)
        #expect(await second.contains("X") == true)

        await second.reset()
        let third = SyncedSampleStore(suiteName: suite)
        #expect(await third.contains("X") == false)
    }

    // MARK: - Payload contract

    @Test func healthKitPayloadCarriesSourceProvenance() throws {
        let payload = BodyMetricPayload(weightKg: 80.4, source: .healthkit)
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(payload)) as? [String: Any]
        )

        #expect(object["weight_kg"] as? Double == 80.4)
        #expect(object["source"] as? String == "healthkit")
    }

    @Test func manualPayloadOmitsSourceSoBackendDefaults() throws {
        // No source → key absent (encodeIfPresent) → backend treats the row as manual.
        let payload = BodyMetricPayload(weightKg: 80.4)
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder.api.encode(payload)) as? [String: Any]
        )

        #expect(object["source"] == nil)
    }

    // MARK: - Summary maths

    @Test func summaryAggregatesCounts() {
        let summary = HealthSyncManager.SyncSummary(weight: 3, bloodPressure: 2, duplicatesSkipped: 5)
        #expect(summary.imported == 5)
        #expect(summary.isEmpty == false)

        let empty = HealthSyncManager.SyncSummary(weight: 0, bloodPressure: 0, duplicatesSkipped: 9)
        #expect(empty.isEmpty == true)
    }

    // MARK: - Sink wiring (in-memory)

    /// An in-memory sink proves the manager's delegation contract compiles and that
    /// uploads round-trip without a backend.
    actor CapturingSink: BodyMetricSyncSink {
        private(set) var uploaded: [BodyMetricPayload] = []
        func upload(_ payload: BodyMetricPayload) async throws { uploaded.append(payload) }
        var count: Int { uploaded.count }
    }

    @Test func managerConstructsWithAnInjectedSink() async {
        let sink = CapturingSink()
        _ = HealthSyncManager(
            sink: sink,
            syncedStore: SyncedSampleStore(suiteName: "test.healthsync.\(UUID().uuidString)")
        )
        // On a non-device platform `sync` reports `.unavailable`; construction and
        // the sink contract are what we assert here.
        #expect(await sink.uploaded.isEmpty)
    }

    /// The default `uploadBatch` falls back to per-item `upload`, so in-memory/test
    /// sinks that only implement `upload` keep working unchanged.
    @Test func defaultUploadBatchFallsBackToPerItemUpload() async throws {
        let sink = CapturingSink()
        try await sink.uploadBatch([
            BodyMetricPayload(weightKg: 80.1, source: .healthkit),
            BodyMetricPayload(weightKg: 80.2, source: .healthkit),
        ])
        #expect(await sink.count == 2)
    }

    /// A sink that overrides `uploadBatch` (like the real `/body-metrics/batch`-backed
    /// one) receives whole batches in a single call rather than item-by-item.
    actor BatchSink: BodyMetricSyncSink {
        private(set) var batches: [[BodyMetricPayload]] = []
        func upload(_ payload: BodyMetricPayload) async throws { batches.append([payload]) }
        func uploadBatch(_ payloads: [BodyMetricPayload]) async throws { batches.append(payloads) }
        var batchCount: Int { batches.count }
    }

    @Test func overriddenUploadBatchReceivesOneCallPerBatch() async throws {
        let sink = BatchSink()
        try await sink.uploadBatch([
            BodyMetricPayload(weightKg: 80.1, source: .healthkit),
            BodyMetricPayload(weightKg: 80.2, source: .healthkit),
            BodyMetricPayload(weightKg: 80.3, source: .healthkit),
        ])
        #expect(await sink.batchCount == 1)
        #expect(await sink.batches.first?.count == 3)
    }
}
