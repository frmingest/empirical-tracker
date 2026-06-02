import Testing
import Foundation
import Core
@testable import HealthSync

/// Sprint 10 — the network-free seams of the Withings **Cloud** client (ADR-023):
/// the DTO decode contracts against the backend's response shapes, and the callback
/// URL discrimination that tells a successful redirect from a user cancel. The OAuth
/// web session and the server-side pull need the live backend and are exercised in the
/// Sprint 12 QA matrix, not here.
struct WithingsCloudTests {

    // MARK: - Connection status decoding

    @Test func connectionStatusDecodesConnected() throws {
        let json = """
        {
            "connected": true,
            "last_sync_at": "2026-06-01T08:30:00.000Z",
            "connected_at": "2026-05-20T12:00:00.000Z"
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder.api.decode(WithingsConnectionStatus.self, from: json)
        #expect(status.connected == true)
        #expect(status.lastSyncAt != nil)
        #expect(status.connectedAt != nil)
    }

    @Test func connectionStatusDecodesDisconnectedWithNullTimestamps() throws {
        let json = """
        { "connected": false, "last_sync_at": null, "connected_at": null }
        """.data(using: .utf8)!

        let status = try JSONDecoder.api.decode(WithingsConnectionStatus.self, from: json)
        #expect(status.connected == false)
        #expect(status.lastSyncAt == nil)
        #expect(status.connectedAt == nil)
    }

    // MARK: - Authorization decoding

    @Test func authorizationDecodesConsentURL() throws {
        let json = """
        {
            "authorize_url": "https://account.withings.com/oauth2_user/authorize2?response_type=code&client_id=abc&scope=user.metrics&redirect_uri=https%3A%2F%2Fapi.example%2Fwithings%2Fcallback&state=xyz",
            "state": "xyz"
        }
        """.data(using: .utf8)!

        let auth = try JSONDecoder.api.decode(WithingsAuthorization.self, from: json)
        #expect(auth.authorizeUrl.host == "account.withings.com")
        #expect(auth.state == "xyz")
    }

    // MARK: - Sync result decoding

    @Test func syncResultDecodesAndReportsEmptiness() throws {
        let json = #"{ "imported": 0, "duplicates_skipped": 4 }"#.data(using: .utf8)!
        let result = try JSONDecoder.api.decode(WithingsSyncResult.self, from: json)
        #expect(result.imported == 0)
        #expect(result.duplicatesSkipped == 4)
        #expect(result.isEmpty == true)

        let json2 = #"{ "imported": 3, "duplicates_skipped": 1 }"#.data(using: .utf8)!
        let result2 = try JSONDecoder.api.decode(WithingsSyncResult.self, from: json2)
        #expect(result2.isEmpty == false)
    }

    // MARK: - Callback discrimination

    @Test func recognisesTheBackendSuccessRedirect() {
        #expect(WithingsCloudService.isSuccessCallback(
            URL(string: "empiricaltracker://withings/connected")!) == true)
        // Scheme is matched case-insensitively (iOS may normalise it).
        #expect(WithingsCloudService.isSuccessCallback(
            URL(string: "EmpiricalTracker://withings")!) == true)
    }

    @Test func rejectsForeignOrMalformedCallbacks() {
        #expect(WithingsCloudService.isSuccessCallback(
            URL(string: "https://account.withings.com/oauth2/authorize")!) == false)
        // Right scheme, wrong host → not our Withings redirect.
        #expect(WithingsCloudService.isSuccessCallback(
            URL(string: "empiricaltracker://healthkit")!) == false)
    }
}
