import Core
import Auth
import Biomarkers
import DietEvents
import FoodDiary
import BodyMetrics
import Account
import HealthSync
import Foundation
import Observation

/// Single app-wide environment object injected into the SwiftUI environment.
/// Owns all repositories and the shared `APIClient`.
/// View models observe individual repositories rather than this container directly.
@MainActor
@Observable
public final class AppEnvironment {

    // MARK: - Auth (Sprint 1)

    public let authStore: AuthStore
    public let settings: SettingsStore

    // MARK: - Networking

    public let client: APIClient

    // MARK: - Repositories

    public let biomarkers: BiomarkersRepository
    public let dietEvents: DietEventsRepository
    public let foodDiary: FoodDiaryRepository
    public let bodyMetrics: BodyMetricsRepository
    public let account: AccountRepository
    public let healthSync: HealthSyncManager

    // MARK: - Convenience passthrough

    /// Shorthand used in legacy callsites; prefer `authStore.isAuthenticated` directly.
    public var isAuthenticated: Bool { authStore.isAuthenticated }

    // MARK: - Init

    public init(authService: any AuthServiceProtocol) {
        let store = AuthStore(service: authService)
        self.authStore = store
        self.settings = SettingsStore()

        let tokenProvider = AuthTokenProvider(authStore: store)
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

    // MARK: - Preview factory

    public static func preview() -> AppEnvironment {
        AppEnvironment(authService: MockAuthService())
    }

    // MARK: - Convenience

    /// Called on every app foreground to refresh the primary read paths.
    public func refreshAll() async {
        async let _ = biomarkers.loadResults()
        async let _ = dietEvents.load()
        async let _ = account.loadSettings()
    }
}
