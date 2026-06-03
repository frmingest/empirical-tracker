import Core
import AppAuth
import Biomarkers
import DietEvents
import FoodDiary
import MealPlans
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

    /// Records explicit consent to health-data processing. Gates the main app
    /// until the user agrees (see `RootView`).
    public let consent: ConsentStore

    // MARK: - Networking

    public let client: APIClient

    // MARK: - Import service (Sprint 4)

    public let biomarkersImport: BiomarkersImportService

    // MARK: - Repositories

    public let biomarkers: BiomarkersRepository
    public let dietEvents: DietEventsRepository
    public let foodDiary: FoodDiaryRepository
    public let mealPlans: MealPlansRepository
    public let bodyMetrics: BodyMetricsRepository
    public let account: AccountRepository
    public let healthSync: HealthSyncManager
    /// Shared Apple Health connection/sync state (Sprint 9). One instance so the
    /// Body tab and Settings show the same connection status. App-internal (the
    /// `HealthSyncState` view-model type lives in the app target, not a package).
    let healthSyncState: HealthSyncState

    /// Withings **Cloud** client (Sprint 10, Path B). Drives the server-to-server
    /// OAuth connection; the backend holds the tokens and runs the webhooks.
    public let withingsCloud: WithingsCloudService
    /// Shared Withings Cloud connection state, app-internal like `healthSyncState`,
    /// so the Body tab and Settings reflect one connection.
    let withingsCloudState: WithingsCloudState

    // MARK: - Convenience passthrough

    /// Shorthand used in legacy callsites; prefer `authStore.isAuthenticated` directly.
    public var isAuthenticated: Bool { authStore.isAuthenticated }

    // MARK: - Init

    public init(authService: any AuthServiceProtocol) {
        let store = AuthStore(service: authService)
        self.authStore = store
        self.settings = SettingsStore()
        self.consent = ConsentStore()

        let tokenProvider = AuthTokenProvider(authStore: store)
        let config = APIClient.Configuration.resolved()
        let apiClient = APIClient(config: config, tokenProvider: tokenProvider)
        self.client = apiClient

        biomarkersImport = BiomarkersImportService(
            baseURL: config.baseURL,
            tokenProvider: tokenProvider
        )
        biomarkers  = BiomarkersRepository(client: apiClient)
        dietEvents  = DietEventsRepository(client: apiClient)
        foodDiary   = FoodDiaryRepository(client: apiClient)
        mealPlans   = MealPlansRepository(client: apiClient)
        bodyMetrics = BodyMetricsRepository(client: apiClient)
        account     = AccountRepository(client: apiClient)

        // HealthKit (Sprint 9): the manager uploads mapped Apple Health readings
        // through the body-metrics repository, tagged `source: healthkit`.
        let syncSink = RepositoryBodyMetricSyncSink(repository: bodyMetrics)
        let manager = HealthSyncManager(sink: syncSink)
        healthSync = manager
        healthSyncState = HealthSyncState(manager: manager, bodyMetrics: bodyMetrics)

        // Withings Cloud (Sprint 10): the backend owns the OAuth token exchange and
        // webhooks; this client starts the connection and reflects status. It stays
        // hidden in the UI until the backend exposes the `/withings/*` endpoints.
        let withingsService = WithingsCloudService(client: apiClient)
        withingsCloud = withingsService
        withingsCloudState = WithingsCloudState(service: withingsService, bodyMetrics: bodyMetrics)
    }

    // MARK: - Preview factory

    public static func preview() -> AppEnvironment {
        AppEnvironment(authService: MockAuthService())
    }

    // MARK: - Convenience

    /// Signs out and clears the local health-data consent flag so the next user
    /// to sign in on this device must give their own consent.
    public func signOut() async {
        await authStore.signOut()
        consent.reset()
    }

    /// Called on every app foreground to refresh the primary read paths.
    public func refreshAll() async {
        async let _ = biomarkers.loadResults()
        async let _ = dietEvents.load()
        async let _ = account.loadSettings()
    }
}
