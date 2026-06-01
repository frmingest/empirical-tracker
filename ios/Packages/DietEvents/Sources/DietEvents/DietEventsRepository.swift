import Core
import Foundation
import Observation

/// Manages diet-event annotations. Shared by biomarker charts and body-metric charts.
/// Mirrors `GET/POST/DELETE /diet-events` in `api/app/diet_events/router.py`.
@MainActor
@Observable
public final class DietEventsRepository {
    public var events: [DietEvent] = []
    public var isLoading = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Fetch

    public func load() async {
        isLoading = true
        error = nil
        do {
            events = try await client.request(.get("/diet-events"))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    // MARK: - Create

    public func create(_ payload: DietEventPayload) async throws {
        let created: DietEvent = try await client.request(.post("/diet-events", body: payload))
        events.append(created)
        events.sort { $0.startedOn < $1.startedOn }
    }

    // MARK: - Delete

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/diet-events/\(id)"))
        events.removeAll { $0.id == id }
    }

    // MARK: - Chart projection helpers

    /// Returns events that intersect the given date range for chart overlay rendering.
    /// Mirrors the snapping logic in `web/src/lib/chartAnnotations.ts`.
    public func events(overlapping start: Date, end: Date) -> [DietEvent] {
        events.filter { event in
            let eventEnd = event.endedOn ?? event.startedOn
            return event.startedOn <= end && eventEnd >= start
        }
    }
}
