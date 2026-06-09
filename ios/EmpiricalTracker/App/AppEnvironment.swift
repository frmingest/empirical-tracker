import Core
import AppAuth
import Biomarkers
import DietEvents
import FoodDiary
import MealPlans
import Recipes
import BodyMetrics
import Account
import HealthSync
import Foundation
import Observation
import WidgetKit

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

    /// First-run profile (height, biological sex) + the setup-completion flag that
    /// gates `ProfileSetupView` after consent.
    public let userProfile: UserProfileStore

    // MARK: - Networking

    public let client: APIClient

    // MARK: - Import service (Sprint 4)

    public let biomarkersImport: BiomarkersImportService

    // MARK: - Repositories

    public let biomarkers: BiomarkersRepository
    public let dietEvents: DietEventsRepository
    public let foodDiary: FoodDiaryRepository
    public let mealPlans: MealPlansRepository
    public let recipes: RecipesRepository
    public let bodyMetrics: BodyMetricsRepository
    public let activityMetrics: ActivityMetricsRepository
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

    let widgetStore = WidgetDataStore()

    // MARK: - Convenience passthrough

    /// Shorthand used in legacy callsites; prefer `authStore.isAuthenticated` directly.
    public var isAuthenticated: Bool { authStore.isAuthenticated }

    // MARK: - Init

    public init(authService: any AuthServiceProtocol) {
        let store = AuthStore(service: authService)
        self.authStore = store
        self.settings = SettingsStore()
        self.consent = ConsentStore()
        self.userProfile = UserProfileStore()

        let tokenProvider = AuthTokenProvider(authStore: store)
        let config = APIClient.Configuration.resolved()
        let apiClient = APIClient(
            config: config,
            tokenProvider: tokenProvider,
            // A 401 means our token is no longer accepted: end the session so the app
            // drops back to the sign-in screen with a clear message rather than leaving
            // the user "logged in" but hitting sync errors on every screen.
            onUnauthorized: { await store.expireSession() }
        )
        self.client = apiClient

        biomarkersImport = BiomarkersImportService(
            baseURL: config.baseURL,
            tokenProvider: tokenProvider
        )
        biomarkers  = BiomarkersRepository(client: apiClient)
        dietEvents  = DietEventsRepository(client: apiClient)
        foodDiary   = FoodDiaryRepository(client: apiClient)
        mealPlans   = MealPlansRepository(client: apiClient)
        recipes     = RecipesRepository(client: apiClient)
        bodyMetrics = BodyMetricsRepository(client: apiClient)
        account     = AccountRepository(client: apiClient)

        // HealthKit (Sprint 9 / ADR-033): the manager uploads mapped Apple Health
        // readings through their respective repositories.
        activityMetrics = ActivityMetricsRepository(client: apiClient)
        let syncSink = RepositoryBodyMetricSyncSink(repository: bodyMetrics)
        let activitySink = RepositoryActivityMetricSyncSink(repository: activityMetrics)
        let manager = HealthSyncManager(sink: syncSink, activitySink: activitySink)
        healthSync = manager
        healthSyncState = HealthSyncState(
            manager: manager,
            bodyMetrics: bodyMetrics,
            activityMetrics: activityMetrics
        )

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

    /// Signs out and clears the local health-data consent flag and profile so the
    /// next user to sign in on this device must give their own consent and is
    /// offered their own first-run setup.
    public func signOut() async {
        await authStore.signOut()
        consent.reset()
        userProfile.reset()
    }

    /// Called on every app foreground to refresh the primary read paths.
    public func refreshAll() async {
        async let _ = biomarkers.loadResults()
        async let _ = dietEvents.load()
        async let _ = account.loadSettings()
        await writeWidgetSnapshot()
    }

    /// Writes the latest snapshot to the App Group container and reloads widget timelines.
    public func writeWidgetSnapshot() async {
        await bodyMetrics.load()
        let todayEntries = foodDiary.entries.filter {
            Calendar.current.isDateInToday($0.loggedOn)
        }
        widgetStore.write(
            biomarkerResults: biomarkers.results,
            bodyMetrics: bodyMetrics.metrics,
            foodEntries: todayEntries
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}
