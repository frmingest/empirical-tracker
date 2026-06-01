import Core
import Biomarkers
import DietEvents
import FoodDiary
import BodyMetrics
import Account
import HealthSync
import Foundation
import Observation

/// Single app-wide environment object injected into the SwiftUI environment.
/// Owns all repositories and the shared `APIClient`. View models observe
/// individual repositories rather than this container directly.
@MainActor
@Observable
public final class AppEnvironment {

    // MARK: - Networking

    public let client: APIClient

    // MARK: - Repositories

    public let biomarkers: BiomarkersRepository
    public let dietEvents: DietEventsRepository
    public let foodDiary: FoodDiaryRepository
    public let bodyMetrics: BodyMetricsRepository
    public let account: AccountRepository
    public let healthSync: HealthSyncManager

    // MARK: - Auth (Sprint 1 — supabase-swift)

    public var isAuthenticated = false
    public var currentUserID: String?

    // MARK: - Init

    public init(tokenProvider: any TokenProvider = AnonymousTokenProvider()) {
        let config = APIClient.Configuration.resolved()
        let apiClient = APIClient(config: config, tokenProvider: tokenProvider)
        self.client = apiClient

        biomarkers  = BiomarkersRepository(client: apiClient)
        dietEvents  = DietEventsRepository(client: apiClient)
        foodDiary   = FoodDiaryRepository(client: apiClient)
        bodyMetrics = BodyMetricsRepository(client: apiClient)
        account     = AccountRepository(client: apiClient)
        healthSync  = HealthSyncManager()
    }

    // MARK: - Convenience

    /// Called on every app foreground to refresh the primary read paths.
    public func refreshAll() async {
        async let _ = biomarkers.loadResults()
        async let _ = dietEvents.load()
        async let _ = account.loadSettings()
    }
}
