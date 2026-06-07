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
        public let restingHeartRate: Int
        public let heartRateVariability: Int
        public let heartRate: Int
        public let duplicatesSkipped: Int
        public let uploadsFailed: Int

        public var imported: Int { weight + bloodPressure + restingHeartRate + heartRateVariability + heartRate }
        public var isEmpty: Bool { imported == 0 }

        public init(
            weight: Int,
            bloodPressure: Int,
            restingHeartRate: Int = 0,
            heartRateVariability: Int = 0,
            heartRate: Int = 0,
            duplicatesSkipped: Int,
            uploadsFailed: Int = 0
        ) {
            self.weight = weight
            self.bloodPressure = bloodPressure
            self.restingHeartRate = restingHeartRate
            self.heartRateVariability = heartRateVariability
            self.heartRate = heartRate
            self.duplicatesSkipped = duplicatesSkipped
            self.uploadsFailed = uploadsFailed
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
    ///
    /// All metric types are queried concurrently via a task group. The dedup store
    /// is flushed once at the end to avoid thousands of UserDefaults writes.
    @discardableResult
    public func sync(types: Set<HealthMetricType>, since: Date? = nil) async throws -> SyncSummary {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }

        var weightCount = 0, bpCount = 0, rhrCount = 0, hrvCount = 0, hrCount = 0
        var totalSkipped = 0, totalFailed = 0

        // Capture any task-group error so we flush the dedup store before rethrowing —
        // partial progress (UUIDs of successfully-uploaded samples) must be persisted.
        var groupError: Error?
        do {
        try await withThrowingTaskGroup(of: (HealthMetricType, SyncCounts).self) { group in
            if types.contains(.weight) {
                group.addTask {
                    let c = try await self.syncPaged(
                        type: HKQuantityType(.bodyMass), since: since,
                        transform: { sample in
                            guard let q = sample as? HKQuantitySample else { return nil }
                            let kg = q.quantity.doubleValue(for: .gramUnit(with: .kilo))
                            guard kg > 0 else { return nil }
                            return WeightReading(uuid: q.uuid.uuidString, date: q.endDate, kg: kg)
                        },
                        key: { $0.uuid },
                        payload: { BodyMetricPayload(measuredOn: Self.dayStart($0.date), weightKg: $0.kg, source: .healthkit) }
                    )
                    return (.weight, c)
                }
            }

            if types.contains(.bloodPressure) {
                group.addTask {
                    let c = try await self.syncPaged(
                        type: HKCorrelationType(.bloodPressure), since: since,
                        transform: { sample in
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
                        },
                        key: { $0.uuid },
                        payload: { BodyMetricPayload(measuredOn: Self.dayStart($0.date), systolic: $0.systolic, diastolic: $0.diastolic, source: .healthkit) }
                    )
                    return (.bloodPressure, c)
                }
            }

            if types.contains(.restingHeartRate) {
                group.addTask {
                    let c = try await self.syncPaged(
                        type: HKQuantityType(.restingHeartRate), since: since,
                        transform: { sample in
                            guard let q = sample as? HKQuantitySample else { return nil }
                            let unit = HKUnit.count().unitDivided(by: .minute())
                            let bpm = q.quantity.doubleValue(for: unit)
                            guard bpm > 0 else { return nil }
                            return HRReading(uuid: q.uuid.uuidString, date: q.endDate, bpm: Int(bpm.rounded()))
                        },
                        key: { $0.uuid },
                        payload: { BodyMetricPayload(measuredOn: Self.dayStart($0.date), restingHeartRateBpm: $0.bpm, source: .healthkit) }
                    )
                    return (.restingHeartRate, c)
                }
            }

            if types.contains(.heartRateVariability) {
                group.addTask {
                    let c = try await self.syncPaged(
                        type: HKQuantityType(.heartRateVariabilitySDNN), since: since,
                        transform: { sample in
                            guard let q = sample as? HKQuantitySample else { return nil }
                            let ms = q.quantity.doubleValue(for: .secondUnit(with: .milli))
                            guard ms > 0 else { return nil }
                            return HRVReading(uuid: q.uuid.uuidString, date: q.endDate, ms: ms)
                        },
                        key: { $0.uuid },
                        payload: { BodyMetricPayload(measuredOn: Self.dayStart($0.date), hrvMs: $0.ms, source: .healthkit) }
                    )
                    return (.heartRateVariability, c)
                }
            }

            if types.contains(.heartRate) {
                // Daily avg HR uses HKStatisticsCollectionQuery (pre-aggregated by HealthKit).
                // Max ~2 200 items for 6 years — small enough to batch-upload in one call.
                group.addTask {
                    var c = SyncCounts()
                    let readings = try await self.readDailyAverageHRSamples(since: since)
                    var payloads: [BodyMetricPayload] = []
                    var keys: [String] = []
                    for reading in readings {
                        if await self.syncedStore.contains(reading.dedupKey) { c.skipped += 1; continue }
                        payloads.append(BodyMetricPayload(measuredOn: reading.day, heartRateBpm: reading.bpm, source: .healthkit))
                        keys.append(reading.dedupKey)
                    }
                    if !payloads.isEmpty {
                        do {
                            try await self.sink.uploadBatch(payloads)
                            for k in keys { await self.syncedStore.insert(k) }
                            c.uploaded += keys.count
                        } catch { c.failed += keys.count }
                    }
                    return (.heartRate, c)
                }
            }

            for try await (type, c) in group {
                totalSkipped += c.skipped
                totalFailed += c.failed
                switch type {
                case .weight:               weightCount = c.uploaded
                case .bloodPressure:        bpCount     = c.uploaded
                case .restingHeartRate:     rhrCount    = c.uploaded
                case .heartRateVariability: hrvCount    = c.uploaded
                case .heartRate:            hrCount     = c.uploaded
                }
            }
        }
        } catch { groupError = error }
        await syncedStore.flush()
        if let groupError { throw groupError }

        return SyncSummary(
            weight: weightCount,
            bloodPressure: bpCount,
            restingHeartRate: rhrCount,
            heartRateVariability: hrvCount,
            heartRate: hrCount,
            duplicatesSkipped: totalSkipped,
            uploadsFailed: totalFailed
        )
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

    // MARK: Sample value types (Sendable so they cross actor boundaries safely)

    private struct WeightReading: Sendable { let uuid: String; let date: Date; let kg: Double }
    private struct BPReading: Sendable { let uuid: String; let date: Date; let systolic: Int; let diastolic: Int }
    private struct HRReading: Sendable { let uuid: String; let date: Date; let bpm: Int }
    private struct HRVReading: Sendable { let uuid: String; let date: Date; let ms: Double }
    private struct DailyAvgHRReading: Sendable { let dedupKey: String; let day: Date; let bpm: Int }

    /// Counters accumulated by each concurrent metric-type task.
    private struct SyncCounts: Sendable { var uploaded = 0; var skipped = 0; var failed = 0 }

    /// HealthKit fetch page size. 500 samples ≈ 1–2 years of daily readings at once,
    /// keeping per-page memory bounded during large initial imports.
    private static let pageSize = 500

    private func stopObservingInternal() {
        for query in observerQueries { store.stop(query) }
        observerQueries.removeAll()
    }

    // MARK: - Paged query + batch upload helpers

    /// Fetches one page of up to `pageSize` samples via `HKAnchoredObjectQuery`.
    /// The `transform` closure runs inside HealthKit's callback so non-Sendable HK
    /// objects never cross the continuation boundary.
    private func anchoredPage<T: Sendable>(
        type: HKSampleType,
        anchor: HKQueryAnchor?,
        since: Date?,
        transform: @escaping @Sendable (HKSample) -> T?
    ) async throws -> (samples: [T], nextAnchor: HKQueryAnchor?, hasMore: Bool) {
        let predicate = since.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let q = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: Self.pageSize
            ) { _, samplesOrNil, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.query(error.localizedDescription))
                    return
                }
                let mapped = (samplesOrNil ?? []).compactMap(transform)
                let hasMore = (samplesOrNil?.count ?? 0) >= Self.pageSize
                continuation.resume(returning: (mapped, newAnchor, hasMore))
            }
            store.execute(q)
        }
    }

    /// Pages through all matching samples of `type`, deduplicates via the sync store,
    /// and uploads new samples in one batch POST per page. Memory usage is bounded to
    /// one page of samples at a time; network calls are bounded to one per page.
    private func syncPaged<T: Sendable>(
        type: HKSampleType,
        since: Date?,
        transform: @escaping @Sendable (HKSample) -> T?,
        key: @Sendable (T) -> String,
        payload: @Sendable (T) -> BodyMetricPayload
    ) async throws -> SyncCounts {
        var c = SyncCounts()
        var anchor: HKQueryAnchor? = nil
        var hasMore = true

        while hasMore {
            let page = try await anchoredPage(type: type, anchor: anchor, since: since, transform: transform)
            anchor = page.nextAnchor
            hasMore = page.hasMore

            var payloads: [BodyMetricPayload] = []
            var keys: [String] = []
            for item in page.samples {
                let k = key(item)
                if await syncedStore.contains(k) { c.skipped += 1; continue }
                payloads.append(payload(item))
                keys.append(k)
            }
            guard !payloads.isEmpty else { continue }
            do {
                try await sink.uploadBatch(payloads)
                for k in keys { await syncedStore.insert(k) }
                c.uploaded += keys.count
            } catch {
                c.failed += keys.count
            }
        }
        return c
    }

    // MARK: - Daily average HR (HKStatisticsCollectionQuery — no raw sample paging needed)

    /// Uses `HKStatisticsCollectionQuery` so HealthKit computes daily averages
    /// internally. Returns one result per calendar day (~2 200 max for 6 years).
    private func readDailyAverageHRSamples(since: Date?) async throws -> [DailyAvgHRReading] {
        let type = HKQuantityType(.heartRate)
        let predicate = since.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }
        let anchorDate = Calendar.current.startOfDay(for: Date())
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { continuation in
            let statsQuery = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            statsQuery.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.query(error.localizedDescription))
                    return
                }
                let unit = HKUnit.count().unitDivided(by: .minute())
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                let readings: [DailyAvgHRReading] = (collection?.statistics() ?? []).compactMap { stat in
                    guard let avg = stat.averageQuantity() else { return nil }
                    let bpm = avg.doubleValue(for: unit)
                    guard bpm > 0 else { return nil }
                    let day = stat.startDate
                    let key = "avg-hr-\(formatter.string(from: day))"
                    return DailyAvgHRReading(dedupKey: key, day: day, bpm: Int(bpm.rounded()))
                }
                continuation.resume(returning: readings.sorted { $0.day < $1.day })
            }
            store.execute(statsQuery)
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
            case .restingHeartRate:
                set.insert(HKQuantityType(.restingHeartRate))
            case .heartRateVariability:
                set.insert(HKQuantityType(.heartRateVariabilitySDNN))
            case .heartRate:
                set.insert(HKQuantityType(.heartRate))
            }
        }
        return set
    }

    private static func observerSampleTypes(for types: Set<HealthMetricType>) -> [HKSampleType] {
        var set: [HKSampleType] = []
        for type in types {
            switch type {
            case .weight:               set.append(HKQuantityType(.bodyMass))
            case .bloodPressure:        set.append(HKCorrelationType(.bloodPressure))
            case .restingHeartRate:     set.append(HKQuantityType(.restingHeartRate))
            case .heartRateVariability: set.append(HKQuantityType(.heartRateVariabilitySDNN))
            case .heartRate:            set.append(HKQuantityType(.heartRate))
            }
        }
        return set
    }

    private static func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    #endif
}
