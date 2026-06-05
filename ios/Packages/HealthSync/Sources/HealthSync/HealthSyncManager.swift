import BodyMetrics
import Core
import Foundation

#if canImport(HealthKit)
import HealthKit
#endif

/// HealthKit integration (Sprint 9, ADR-022).
///
/// Withings devices write to Apple Health through the user's **Health Mate** app;
/// this manager reads those samples back out and maps them onto `body_metrics`
/// rows tagged `source: healthkit`. It covers the two signals that fit the existing
/// table — **weight** and **blood pressure** — requesting read authorization only
/// for those, querying history on connect, observing for background updates, and
/// deduping by HealthKit sample UUID so re-syncs never double-insert.
///
/// All HealthKit access is guarded by `#if canImport(HealthKit)` so the package
/// still builds on platforms without the framework (the methods then report
/// `.unavailable`). The actual upload is delegated to a `BodyMetricSyncSink`.
public actor HealthSyncManager {

    // MARK: - Sync summary

    public struct SyncSummary: Sendable, Equatable {
        public let weight: Int
        public let bloodPressure: Int
        public let duplicatesSkipped: Int

        public var imported: Int { weight + bloodPressure }
        public var isEmpty: Bool { imported == 0 }

        public init(weight: Int, bloodPressure: Int, duplicatesSkipped: Int) {
            self.weight = weight
            self.bloodPressure = bloodPressure
            self.duplicatesSkipped = duplicatesSkipped
        }
    }

    // MARK: - Dependencies

    private let sink: any BodyMetricSyncSink
    private let syncedStore: SyncedSampleStore

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    #endif

    public init(
        sink: any BodyMetricSyncSink,
        syncedStore: SyncedSampleStore = SyncedSampleStore()
    ) {
        self.sink = sink
        self.syncedStore = syncedStore
    }

    /// Whether HealthKit can be used on this device at all.
    public static var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    // MARK: - Authorization

    /// Presents the system permission sheet for the read types backing `types`.
    /// HealthKit never reveals read-authorization status (by design, for privacy),
    /// so a non-throwing return means only "the user has made a choice" — the app
    /// infers connection from that plus whether subsequent syncs return data.
    public func requestAuthorization(for types: Set<HealthMetricType>) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        let readTypes = Self.readObjectTypes(for: types)
        guard !readTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        #else
        throw HealthSyncError.unavailable
        #endif
    }

    // MARK: - Historical / manual sync

    /// Reads samples for the enabled `types`, skips any already uploaded (by sample
    /// UUID), pushes the rest via the sink as `source: healthkit`, and records the
    /// UUIDs it successfully uploaded. Returns a count summary.
    ///
    /// - Parameter since: optional lower bound; `nil` imports the full history.
    @discardableResult
    public func sync(types: Set<HealthMetricType>, since: Date? = nil) async throws -> SyncSummary {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }

        var weightCount = 0
        var bpCount = 0
        var skipped = 0

        if types.contains(.weight) {
            for reading in try await readWeightSamples(since: since) {
                if await syncedStore.contains(reading.uuid) { skipped += 1; continue }
                try await sink.upload(BodyMetricPayload(
                    measuredOn: Self.dayStart(reading.date),
                    weightKg: reading.kg,
                    source: .healthkit
                ))
                await syncedStore.insert(reading.uuid)
                weightCount += 1
            }
        }

        if types.contains(.bloodPressure) {
            for reading in try await readBloodPressureSamples(since: since) {
                if await syncedStore.contains(reading.uuid) { skipped += 1; continue }
                try await sink.upload(BodyMetricPayload(
                    measuredOn: Self.dayStart(reading.date),
                    systolic: reading.systolic,
                    diastolic: reading.diastolic,
                    source: .healthkit
                ))
                await syncedStore.insert(reading.uuid)
                bpCount += 1
            }
        }

        return SyncSummary(weight: weightCount, bloodPressure: bpCount, duplicatesSkipped: skipped)
        #else
        throw HealthSyncError.unavailable
        #endif
    }

    // MARK: - Background observation

    /// Registers observer queries with background delivery for the enabled types so
    /// new Withings → Apple Health readings trigger `onUpdate` while the app is
    /// backgrounded. Background delivery is best-effort (documented in ADR-022); the
    /// "Sync now" button is the reliable fallback.
    public func startObserving(
        types: Set<HealthMetricType>,
        onUpdate: @escaping @Sendable () async -> Void
    ) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        stopObservingInternal()

        for sampleType in Self.observerSampleTypes(for: types) {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completion, error in
                // `completion()` must be called so HealthKit stops retrying delivery.
                guard error == nil else { completion(); return }
                Task {
                    await onUpdate()
                    completion()
                }
            }
            store.execute(query)
            observerQueries.append(query)
            try await store.enableBackgroundDelivery(for: sampleType, frequency: .hourly)
        }
        #else
        throw HealthSyncError.unavailable
        #endif
    }

    /// Clears the local UUID dedup cache so the next sync re-imports all history.
    public func resetSyncedSamples() async {
        await syncedStore.reset()
    }

    /// Tears down observers and disables background delivery (called on disconnect).
    public func stopObserving() async {
        #if canImport(HealthKit)
        stopObservingInternal()
        try? await store.disableAllBackgroundDelivery()
        #endif
    }

    // MARK: - HealthKit internals

    #if canImport(HealthKit)
    private struct WeightReading: Sendable {
        let uuid: String
        let date: Date
        let kg: Double
    }

    private struct BPReading: Sendable {
        let uuid: String
        let date: Date
        let systolic: Int
        let diastolic: Int
    }

    private func stopObservingInternal() {
        for query in observerQueries { store.stop(query) }
        observerQueries.removeAll()
    }

    private func readWeightSamples(since: Date?) async throws -> [WeightReading] {
        try await query(type: HKQuantityType(.bodyMass), since: since) { sample in
            guard let q = sample as? HKQuantitySample else { return nil }
            let kg = q.quantity.doubleValue(for: .gramUnit(with: .kilo))
            guard kg > 0 else { return nil }
            return WeightReading(uuid: q.uuid.uuidString, date: q.endDate, kg: kg)
        }
    }

    private func readBloodPressureSamples(since: Date?) async throws -> [BPReading] {
        // HealthKit type/unit objects aren't `Sendable`, so build them inside the
        // `@Sendable` transform rather than capturing them.
        try await query(type: HKCorrelationType(.bloodPressure), since: since) { sample in
            guard let correlation = sample as? HKCorrelation else { return nil }
            let unit = HKUnit.millimeterOfMercury()
            guard
                let sys = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample,
                let dia = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample
            else { return nil }
            return BPReading(
                uuid: correlation.uuid.uuidString,
                date: correlation.endDate,
                systolic: Int(sys.quantity.doubleValue(for: unit).rounded()),
                diastolic: Int(dia.quantity.doubleValue(for: unit).rounded())
            )
        }
    }

    /// Bridges the completion-based `HKSampleQuery` into async/await. The `transform`
    /// runs **inside** the result handler so only the mapped `Sendable` values cross
    /// the continuation boundary (HealthKit samples themselves aren't `Sendable`).
    /// Ascending by end date so charts and history see oldest-first order.
    private func query<T: Sendable>(
        type: HKSampleType,
        since: Date?,
        transform: @escaping @Sendable (HKSample) -> T?
    ) async throws -> [T] {
        let predicate = since.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.query(error.localizedDescription))
                } else {
                    continuation.resume(returning: (samples ?? []).compactMap(transform))
                }
            }
            store.execute(query)
        }
    }

    private static func readObjectTypes(for types: Set<HealthMetricType>) -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for type in types {
            switch type {
            case .weight:
                set.insert(HKQuantityType(.bodyMass))
            case .bloodPressure:
                set.insert(HKQuantityType(.bloodPressureSystolic))
                set.insert(HKQuantityType(.bloodPressureDiastolic))
            }
        }
        return set
    }

    private static func observerSampleTypes(for types: Set<HealthMetricType>) -> [HKSampleType] {
        var set: [HKSampleType] = []
        for type in types {
            switch type {
            case .weight:        set.append(HKQuantityType(.bodyMass))
            case .bloodPressure: set.append(HKCorrelationType(.bloodPressure))
            }
        }
        return set
    }

    private static func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    #endif
}
