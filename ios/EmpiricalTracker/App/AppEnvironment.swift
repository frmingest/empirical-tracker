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

    /// Opt-in local reminder preferences (meal / weigh-in / lab cadence). Scheduled
    /// on-device via `ReminderScheduler`; nothing reaches the backend.
    public let reminders = ReminderPreferencesStore()

    /// Optional daily intake targets the diary totals are read against (energy,
    /// protein incl. g/kg quick-set, carb ceiling). Device-local (WISHLIST #6).
    public let nutritionTargets = NutritionTargetsStore()

    /// Device-local buffer of recently logged foods for one-tap re-logging in the
    /// food search sheet.
    public let recentFoods = RecentFoodsStore()

    /// Device-local "did I log today?" record behind the quiet streak / last-7-days
    /// line in the food diary.
    public let loggingActivity = LoggingActivityStore()

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

    /// True when this environment is the seeded, local-only sample-data world
    /// (see `sampleData()`). Views use it to hide actions that need a real account
    /// (lab import), and the widget write-through is suppressed so sample numbers
    /// never reach the Home Screen.
    public private(set) var isSampleData = false

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

    // MARK: - Sample-data factory

    /// A self-contained environment seeded with `MockData` and pinned to local-only
    /// repositories, so a brand-new user can browse a populated dashboard — the
    /// diet-event ⇄ biomarker correlation story — before importing a single panel.
    /// Nothing in this environment ever reaches the network or the real account.
    public static func sampleData() -> AppEnvironment {
        let env = AppEnvironment(authService: MockAuthService())
        env.isSampleData = true

        env.biomarkers.isLocalOnly      = true
        env.dietEvents.isLocalOnly      = true
        env.account.isLocalOnly         = true
        env.bodyMetrics.isLocalOnly     = true
        env.activityMetrics.isLocalOnly = true

        env.biomarkers.results      = MockData.biomarkerSeries
        env.dietEvents.events       = MockData.dietEvents
        env.bodyMetrics.metrics     = MockData.bodyMetrics
        env.activityMetrics.metrics = MockData.activityMetrics
        return env
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

    /// Re-arms the local reminders from current preferences. The lab-cadence nudge is
    /// anchored to the most recent panel in memory; when panels haven't been fetched
    /// yet the scheduler keeps the previously stored fire date.
    public func syncReminders() async {
        guard !isSampleData else { return }
        await ReminderScheduler.sync(
            prefs: reminders,
            latestPanelDate: biomarkers.panels.map(\.testedAt).max()
        )
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
        guard !isSampleData else { return }
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
