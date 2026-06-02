import BodyMetrics
import Foundation

/// Where `HealthSyncManager` sends the rows it maps out of Apple Health.
///
/// The manager itself is backend-agnostic: it knows how to read HealthKit, map
/// samples to `BodyMetricPayload`s, and dedupe, but delegates the actual upload so
/// the app layer owns the `POST /body-metrics` (and so tests can use an in-memory
/// sink). Conformers are typically `@MainActor` (they wrap a repository); the
/// protocol is `Sendable` so the actor can hold one across isolation boundaries.
public protocol BodyMetricSyncSink: Sendable {
    /// Persist one HealthKit-sourced reading. Throwing aborts that reading's sync
    /// (its sample UUID is *not* recorded, so a later sync retries it).
    func upload(_ payload: BodyMetricPayload) async throws
}
