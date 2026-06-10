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

    // MARK: - Upload batching

    /// One day's worth of readings, ready to upload as a single merged payload.
    ///
    /// `keys` holds all HealthKit sample UUIDs that contributed to this payload
    /// (one per metric type). All keys are recorded in the dedup store only once
    /// the batch upload succeeds — so a partial failure retries the whole day.
    private struct PendingUpload: Sendable {
        let keys: [String]
        let payload: BodyMetricPayload
    }

    private struct Counts: Sendable { var uploaded = 0; var skipped = 0; var failed = 0 }

    /// Matches the backend's `/body-metrics/batch` cap (router.py). Each batch is one
    /// network round-trip, so a 6-year history of ~daily readings is a handful of
    /// requests rather than thousands.
    private static let maxBatchSize = 500

    /// Groups single-metric readings from multiple types by calendar day and merges
    /// them into one `PendingUpload` per day.
    ///
    /// Without merging, five concurrent HealthKit queries (weight, BP, resting HR,
    /// HRV, avg HR) each create their own payload for the same day, resulting in up
    /// to 5 rows per day in `body_metrics`. Over 7 years that inflates the table to
    /// 12 000+ rows — exceeding the list endpoint cap and silently cutting off the
    /// most-recent data. Merging here collapses all same-day payloads into one row.
    private static func mergeByDay(_ readings: [PendingUpload]) -> [PendingUpload] {
        var byDay: [(dayKey: String, date: Date, keys: [String], payload: BodyMetricPayload)] = []
        var indexByDay: [String: Int] = [:]

        for reading in readings {
            // Group on the *local* calendar day — the same day `measured_on` is
            // encoded under (CalendarDate), so merge keys match wire dates.
            let dayKey = CalendarDate.string(from: reading.payload.measuredOn)
            if let idx = indexByDay[dayKey] {
                // Merge: keep non-nil values from the existing entry, fill in
                // any nil fields from the incoming reading.
                let existing = byDay[idx]
                let p = existing.payload, q = reading.payload
                byDay[idx] = (
                    dayKey: dayKey,
                    date: existing.date,
                    keys: existing.keys + reading.keys,
                    payload: BodyMetricPayload(
                        measuredOn:            p.measuredOn,
                        weightKg:              p.weightKg              ?? q.weightKg,
                        waistCm:               p.waistCm               ?? q.waistCm,
                        systolic:              p.systolic               ?? q.systolic,
                        diastolic:             p.diastolic              ?? q.diastolic,
                        heartRateBpm:          p.heartRateBpm          ?? q.heartRateBpm,
                        restingHeartRateBpm:   p.restingHeartRateBpm   ?? q.restingHeartRateBpm,
                        hrvMs:                 p.hrvMs                 ?? q.hrvMs,
                        note:                  p.note                  ?? q.note,
                        source:                p.source                ?? q.source
                    )
                )
            } else {
                indexByDay[dayKey] = byDay.count
                byDay.append((dayKey: dayKey, date: reading.payload.measuredOn, keys: reading.keys, payload: reading.payload))
            }
        }

        return byDay.map { PendingUpload(keys: $0.keys, payload: $0.payload) }
    }

    /// Filters out already-synced readings, then uploads the rest in `maxBatchSize`
    /// chunks. A chunk's dedup keys are recorded only after its batch upload succeeds,
    /// so a failed chunk is retried on the next sync (never silently dropped, never
    /// double-inserted). Keys are inserted in memory only here — `sync()` flushes the
    /// store once at the end.
    private func uploadPending(_ readings: [PendingUpload]) async -> Counts {
        var c = Counts()
        var pending: [PendingUpload] = []
        pending.reserveCapacity(readings.count)
        for reading in readings {
            // A day is considered already-synced when ALL its contributing sample
            // keys are in the dedup store (i.e. it was fully uploaded before).
            var allSynced = true
            for key in reading.keys {
                if await !syncedStore.contains(key) { allSynced = false; break }
            }
            if allSynced { c.skipped += 1 } else { pending.append(reading) }
        }

        var index = 0
        while index < pending.count {
            let chunk = Array(pending[index..<min(index + Self.maxBatchSize, pending.count)])
            index += Self.maxBatchSize
            do {
                try await sink.uploadBatch(chunk.map(\.payload))
                for reading in chunk {
                    for key in reading.keys { await syncedStore.insert(key) }
                }
                c.uploaded += chunk.count
            } catch {
                c.failed += chunk.count
            }
        }
        return c
    }

    // MARK: - Dependencies

    private let sink: any BodyMetricSyncSink
    private let activitySink: (any ActivityMetricSyncSink)?
    private let syncedStore: SyncedSampleStore

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    #endif

    public init(
        sink: any BodyMetricSyncSink,
        activitySink: (any ActivityMetricSyncSink)? = nil,
        syncedStore: SyncedSampleStore = SyncedSampleStore()
    ) {
        self.sink = sink
        self.activitySink = activitySink
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

    /// Presents the system permission sheet for the read types backing `activityTypes`.
    public func requestAuthorization(for activityTypes: Set<ActivityMetricType>) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        let readTypes = Self.activityReadObjectTypes(for: activityTypes)
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
    /// All metric types are queried concurrently via a task group, and each type's new
    /// readings are uploaded in batches (≤500, the backend's `/body-metrics/batch`
    /// limit) rather than one request per reading. The dedup store is flushed once at
    /// the end to avoid thousands of UserDefaults writes.
    @discardableResult
    public func sync(types: Set<HealthMetricType>, since: Date? = nil) async throws -> SyncSummary {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }

        var totalSkipped = 0, totalFailed = 0, totalUploaded = 0

        // Phase 1: query all metric types concurrently, collecting raw single-field
        // PendingUploads. We do NOT upload yet — merging by day happens next.
        var allPending: [PendingUpload] = []
        var groupError: Error?
        do {
        try await withThrowingTaskGroup(of: [PendingUpload].self) { group in
            if types.contains(.weight) {
                group.addTask {
                    try await self.readWeightSamples(since: since).map {
                        PendingUpload(keys: [$0.uuid], payload: BodyMetricPayload(
                            measuredOn: Self.dayStart($0.date),
                            weightKg: $0.kg,
                            source: .healthkit
                        ))
                    }
                }
            }
            if types.contains(.bloodPressure) {
                group.addTask {
                    try await self.readBloodPressureSamples(since: since).map {
                        PendingUpload(keys: [$0.uuid], payload: BodyMetricPayload(
                            measuredOn: Self.dayStart($0.date),
                            systolic: $0.systolic,
                            diastolic: $0.diastolic,
                            source: .healthkit
                        ))
                    }
                }
            }
            if types.contains(.restingHeartRate) {
                group.addTask {
                    try await self.readRestingHRSamples(since: since).map {
                        PendingUpload(keys: [$0.uuid], payload: BodyMetricPayload(
                            measuredOn: Self.dayStart($0.date),
                            restingHeartRateBpm: $0.bpm,
                            source: .healthkit
                        ))
                    }
                }
            }
            if types.contains(.heartRateVariability) {
                group.addTask {
                    try await self.readHRVSamples(since: since).map {
                        PendingUpload(keys: [$0.uuid], payload: BodyMetricPayload(
                            measuredOn: Self.dayStart($0.date),
                            hrvMs: $0.ms,
                            source: .healthkit
                        ))
                    }
                }
            }
            if types.contains(.heartRate) {
                group.addTask {
                    try await self.readDailyAverageHRSamples(since: since).map {
                        PendingUpload(keys: [$0.dedupKey], payload: BodyMetricPayload(
                            measuredOn: $0.day,
                            heartRateBpm: $0.bpm,
                            source: .healthkit
                        ))
                    }
                }
            }
            for try await batch in group { allPending.append(contentsOf: batch) }
        }
        } catch { groupError = error }

        // Phase 2: merge all same-day readings across metric types into one payload
        // per day, then upload. This prevents the N-rows-per-day table inflation that
        // would silently truncate recent data under the list endpoint's row cap.
        let merged = Self.mergeByDay(allPending)
        let c = await uploadPending(merged)
        totalUploaded = c.uploaded
        totalSkipped  = c.skipped
        totalFailed   = c.failed

        await syncedStore.flush()
        if let groupError { throw groupError }

        // Per-type counts are no longer meaningful after day-merging (one uploaded
        // row may contain weight + HR + HRV). Report the total in `weight` so the
        // summary line shows "Imported: N readings" rather than all zeros.
        return SyncSummary(
            weight: totalUploaded,
            bloodPressure: 0,
            restingHeartRate: 0,
            heartRateVariability: 0,
            heartRate: 0,
            duplicatesSkipped: totalSkipped,
            uploadsFailed: totalFailed
        )
        #else
        throw HealthSyncError.unavailable
        #endif
    }

    // MARK: - Activity sync (ADR-033)

    /// Reads daily sums for the enabled `activityTypes` using
    /// `HKStatisticsCollectionQuery` (cumulative sum per day), then uploads them
    /// via the `activitySink` as a single batch UPSERT per trailing window.
    ///
    /// Dedup is by deterministic **day-key** (not sample UUID), because daily
    /// totals are mutable — today's step count grows until midnight and even past
    /// days can gain late-arriving samples. The trailing window default (7 days)
    /// ensures partial days settle to their final totals on the next sync.
    ///
    /// - Parameter since: lower bound for the query; `nil` imports the full history.
    @discardableResult
    public func syncActivity(types: Set<ActivityMetricType>, since: Date? = nil) async throws -> Int {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        guard let activitySink else { return 0 }

        var allReadings: [ActivityDayReading] = []
        var groupError: Error?
        do {
            try await withThrowingTaskGroup(of: [ActivityDayReading].self) { group in
                if types.contains(.steps) {
                    group.addTask { try await self.readDailySteps(since: since) }
                }
                if types.contains(.activeEnergy) {
                    group.addTask { try await self.readDailyActiveEnergy(since: since) }
                }
                if types.contains(.exerciseMinutes) {
                    group.addTask { try await self.readDailyExerciseMinutes(since: since) }
                }
                for try await batch in group { allReadings.append(contentsOf: batch) }
            }
        } catch { groupError = error }

        // Merge all types into one payload per calendar day.
        let payloads = Self.mergeActivityByDay(allReadings)
        if !payloads.isEmpty {
            var index = 0
            while index < payloads.count {
                let chunk = Array(payloads[index..<min(index + Self.maxBatchSize, payloads.count)])
                index += Self.maxBatchSize
                try await activitySink.uploadBatch(chunk)
            }
        }
        if let groupError { throw groupError }
        return payloads.count
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
        activityTypes: Set<ActivityMetricType> = [],
        onUpdate: @escaping @Sendable () async -> Void
    ) async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSyncError.unavailable }
        stopObservingInternal()

        let allSampleTypes = Self.observerSampleTypes(for: types)
            + Self.activityObserverSampleTypes(for: activityTypes)
        for sampleType in allSampleTypes {
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

    private struct HRReading: Sendable {
        let uuid: String
        let date: Date
        let bpm: Int
    }

    private struct HRVReading: Sendable {
        let uuid: String
        let date: Date
        let ms: Double
    }

    private struct DailyAvgHRReading: Sendable {
        let dedupKey: String
        let day: Date
        let bpm: Int
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

    private func readRestingHRSamples(since: Date?) async throws -> [HRReading] {
        try await query(type: HKQuantityType(.restingHeartRate), since: since) { sample in
            guard let q = sample as? HKQuantitySample else { return nil }
            // Build unit inside the @Sendable closure — HKUnit isn't Sendable.
            let unit = HKUnit.count().unitDivided(by: .minute())
            let bpm = q.quantity.doubleValue(for: unit)
            guard bpm > 0 else { return nil }
            return HRReading(uuid: q.uuid.uuidString, date: q.endDate, bpm: Int(bpm.rounded()))
        }
    }

    private func readHRVSamples(since: Date?) async throws -> [HRVReading] {
        try await query(type: HKQuantityType(.heartRateVariabilitySDNN), since: since) { sample in
            guard let q = sample as? HKQuantitySample else { return nil }
            let ms = q.quantity.doubleValue(for: .secondUnit(with: .milli))
            guard ms > 0 else { return nil }
            return HRVReading(uuid: q.uuid.uuidString, date: q.endDate, ms: ms)
        }
    }

    /// Uses `HKStatisticsCollectionQuery` to compute daily averages inside HealthKit's
    /// own process rather than loading every raw HR sample (potentially 1M+ readings
    /// for Watch users). HealthKit returns one `HKStatistics` per calendar day with
    /// `averageQuantity()` already computed.
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
                let readings: [DailyAvgHRReading] = (collection?.statistics() ?? []).compactMap { stat in
                    guard let avg = stat.averageQuantity() else { return nil }
                    let bpm = avg.doubleValue(for: unit)
                    guard bpm > 0 else { return nil }
                    let day = stat.startDate
                    // Dedup key on the *local* calendar day (stat.startDate is local
                    // midnight) so it names the same day the row is stored under.
                    let key = "avg-hr-\(CalendarDate.string(from: day))"
                    return DailyAvgHRReading(dedupKey: key, day: day, bpm: Int(bpm.rounded()))
                }
                continuation.resume(returning: readings.sorted { $0.day < $1.day })
            }
            store.execute(statsQuery)
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

    // MARK: - Activity HealthKit internals

    private struct ActivityDayReading: Sendable {
        let day: Date
        let steps: Int?
        let activeEnergyKcal: Double?
        let exerciseMinutes: Int?
    }

    private func readDailySteps(since: Date?) async throws -> [ActivityDayReading] {
        try await statisticsCollection(
            type: HKQuantityType(.stepCount),
            options: .cumulativeSum,
            since: since
        ) { stat in
            guard let sum = stat.sumQuantity() else { return nil }
            let value = Int(sum.doubleValue(for: .count()).rounded())
            guard value > 0 else { return nil }
            return ActivityDayReading(day: stat.startDate, steps: value, activeEnergyKcal: nil, exerciseMinutes: nil)
        }
    }

    private func readDailyActiveEnergy(since: Date?) async throws -> [ActivityDayReading] {
        try await statisticsCollection(
            type: HKQuantityType(.activeEnergyBurned),
            options: .cumulativeSum,
            since: since
        ) { stat in
            guard let sum = stat.sumQuantity() else { return nil }
            let kcal = sum.doubleValue(for: .kilocalorie())
            guard kcal > 0 else { return nil }
            return ActivityDayReading(day: stat.startDate, steps: nil, activeEnergyKcal: kcal, exerciseMinutes: nil)
        }
    }

    private func readDailyExerciseMinutes(since: Date?) async throws -> [ActivityDayReading] {
        try await statisticsCollection(
            type: HKQuantityType(.appleExerciseTime),
            options: .cumulativeSum,
            since: since
        ) { stat in
            guard let sum = stat.sumQuantity() else { return nil }
            let minutes = Int(sum.doubleValue(for: .minute()).rounded())
            guard minutes > 0 else { return nil }
            return ActivityDayReading(day: stat.startDate, steps: nil, activeEnergyKcal: nil, exerciseMinutes: minutes)
        }
    }

    /// Generic bridge for `HKStatisticsCollectionQuery` (cumulative sum, one-day interval).
    private func statisticsCollection<T: Sendable>(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        since: Date?,
        transform: @escaping @Sendable (HKStatistics) -> T?
    ) async throws -> [T] {
        let predicate = since.map {
            HKQuery.predicateForSamples(withStart: $0, end: nil, options: .strictStartDate)
        }
        let anchorDate = Calendar.current.startOfDay(for: Date())
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { continuation in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthSyncError.query(error.localizedDescription))
                    return
                }
                let results: [T] = (collection?.statistics() ?? []).compactMap(transform)
                continuation.resume(returning: results)
            }
            store.execute(q)
        }
    }

    /// Merges per-type daily readings into one `ActivityMetricPayload` per calendar day.
    private static func mergeActivityByDay(_ readings: [ActivityDayReading]) -> [ActivityMetricPayload] {
        var byDay: [String: (date: Date, steps: Int?, kcal: Double?, minutes: Int?)] = [:]
        for r in readings {
            // Local calendar day, matching the `measured_on` wire encoding.
            let key = CalendarDate.string(from: r.day)
            if var existing = byDay[key] {
                if let s = r.steps { existing.steps = s }
                if let k = r.activeEnergyKcal { existing.kcal = k }
                if let m = r.exerciseMinutes { existing.minutes = m }
                byDay[key] = existing
            } else {
                byDay[key] = (date: r.day, steps: r.steps, kcal: r.activeEnergyKcal, minutes: r.exerciseMinutes)
            }
        }
        return byDay.values
            .sorted { $0.date < $1.date }
            .map { entry in
                ActivityMetricPayload(
                    measuredOn: entry.date,
                    steps: entry.steps,
                    activeEnergyKcal: entry.kcal,
                    exerciseMinutes: entry.minutes
                )
            }
    }

    private static func activityReadObjectTypes(for types: Set<ActivityMetricType>) -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for type in types {
            switch type {
            case .steps:           set.insert(HKQuantityType(.stepCount))
            case .activeEnergy:    set.insert(HKQuantityType(.activeEnergyBurned))
            case .exerciseMinutes: set.insert(HKQuantityType(.appleExerciseTime))
            }
        }
        return set
    }

    private static func activityObserverSampleTypes(for types: Set<ActivityMetricType>) -> [HKSampleType] {
        types.map { type in
            switch type {
            case .steps:           HKQuantityType(.stepCount)
            case .activeEnergy:    HKQuantityType(.activeEnergyBurned)
            case .exerciseMinutes: HKQuantityType(.appleExerciseTime)
            }
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
