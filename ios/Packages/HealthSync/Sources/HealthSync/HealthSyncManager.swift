import Core
import Foundation

/// HealthKit integration stub — fully implemented in Sprint 9.
///
/// Responsibilities (Sprint 9):
/// - Request HKHealthStore authorization for body mass, BP, resting HR, body fat, lean mass.
/// - Query historical samples on first connect.
/// - Register HKObserverQuery + background delivery for new Withings → Apple Health data.
/// - Deduplicate against existing `body_metrics` rows using HealthKit UUID.
/// - Post sync results to `POST /body-metrics` with `source: healthkit`.
///
/// This stub exposes the public interface so app-layer code compiles today.
public actor HealthSyncManager {

    public enum AuthorizationStatus: Sendable {
        case notDetermined
        case authorized
        case denied
    }

    public private(set) var authorizationStatus: AuthorizationStatus = .notDetermined

    public init() {}

    /// Request HealthKit read authorization. Calls into HKHealthStore in Sprint 9.
    public func requestAuthorization() async throws {
        // Sprint 9: replace with HKHealthStore.requestAuthorization(toShare:read:)
        authorizationStatus = .notDetermined
    }

    /// Pull historical HealthKit samples and upload to the backend.
    public func syncHistorical() async throws {
        // Sprint 9: HKSampleQuery for body mass + BP + resting HR
    }

    /// Register observer queries for background HealthKit delivery.
    public func startObserving() async throws {
        // Sprint 9: HKObserverQuery + enableBackgroundDelivery
    }
}
