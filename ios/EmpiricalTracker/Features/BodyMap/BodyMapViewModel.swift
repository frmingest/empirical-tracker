import Biomarkers
import Core
import Foundation
import Observation

/// Body-region grouping shown on the Body Map.
struct BodyRegion: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    /// Asset name of the organ illustration shown at the top of
    /// `OrganDetailView`. Empty string when no dedicated illustration exists
    /// yet — the view falls back to a large `systemImage` glyph.
    let primaryOrganImage: String
    /// Optional second illustration shown alongside the primary one (e.g.
    /// lungs beside the heart for the cardio-respiratory region).
    let secondaryOrganImage: String?
    /// Tappable hit-area over the silhouette, in body-relative coordinates
    /// (0–1, origin = top-left of the *body* bounding box — see
    /// `BodyMapCanvas.bodyMinX/MaxX/MinY/MaxY`).
    let hitRect: CGRect
    let categories: [BiomarkerCategory]
    var items: [BiomarkerWithSeries] = []

    var worstAssessment: MarkerSignals.Assessment {
        items.map { MarkerSignals.assessment(for: $0) }
            .max { $0.rank < $1.rank } ?? .unknown
    }
}

private extension MarkerSignals.Assessment {
    var rank: Int {
        switch self {
        case .outOfRange: return 3
        case .watch:      return 2
        case .inRange:    return 1
        case .unknown:    return 0
        }
    }
}

@MainActor
@Observable
final class BodyMapViewModel {
    /// Static region skeleton (anchors + categories). Items are filled in on the
    /// fly from the live repository — see `regions`.
    private let regionLayout: [BodyRegion] = BodyMapViewModel.makeRegions()
    private(set) var isLoading = false
    /// When `true`, each marker is judged on its single most recent result only —
    /// the simplest possible read of "where do things stand right now".
    private(set) var showLatestOnly = true
    var errorMessage: String?

    private let biomarkersRepo: BiomarkersRepository

    init(biomarkersRepo: BiomarkersRepository) {
        self.biomarkersRepo = biomarkersRepo
    }

    /// Regions with their markers distributed from the live repository results.
    ///
    /// Deliberately *computed*, not a cached stored property: SwiftUI's
    /// `@Observable` tracking sees the reads of `biomarkersRepo.results` and
    /// `showLatestOnly` while the view body evaluates, so the silhouette
    /// re-renders automatically whenever results change — after a delete-all or
    /// a fresh import — without waiting for the view's `.task` to run again.
    /// (A previous stored-property version went stale on delete and only
    /// refreshed after a logout/login rebuilt the view model.)
    var regions: [BodyRegion] {
        distribute(biomarkersRepo.results)
    }

    func load() async {
        // Fetch from the network only when nothing is loaded yet. An empty store
        // after a delete-all is a valid, intentional state — not a cache miss —
        // so we must not treat "empty" as a reason to keep hammering the API.
        if biomarkersRepo.results.isEmpty {
            isLoading = true
            await biomarkersRepo.loadResults()
            isLoading = false
            if let err = biomarkersRepo.error {
                errorMessage = err.localizedDescription
            }
        }
    }

    func toggleLatestOnly() {
        showLatestOnly.toggle()
    }

    /// The most recent year that appears anywhere in the loaded results — "latest
    /// results" means the most recent test round, not each marker's own latest
    /// (which could span several different years and read as inconsistent).
    private func latestYear(in results: [BiomarkerWithSeries]) -> Int? {
        let cal = Calendar.current
        return results
            .flatMap { $0.series }
            .map { cal.component(.year, from: $0.testedAt) }
            .max()
    }

    private func distribute(_ results: [BiomarkerWithSeries]) -> [BodyRegion] {
        let cal = Calendar.current
        let year = showLatestOnly ? latestYear(in: results) : nil

        var updated = regionLayout
        for i in updated.indices {
            let cats = updated[i].categories
            updated[i].items = results
                .filter { cats.contains(biomarkerCategory(for: $0.biomarker.nameNo)) }
                .compactMap { item -> BiomarkerWithSeries? in
                    guard let year else { return item }
                    let filtered = item.series.filter { cal.component(.year, from: $0.testedAt) == year }
                    return filtered.isEmpty ? nil : BiomarkerWithSeries(biomarker: item.biomarker, series: filtered)
                }
        }
        return updated
    }

    // MARK: - Static layout

    private static func makeRegions() -> [BodyRegion] {
        [
            // ── Neck ──────────────────────────────────────────────────────
            BodyRegion(
                id: "thyroid",
                label: "Thyroid",
                systemImage: "waveform.path.ecg",
                primaryOrganImage: "OrganThyroid",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.36, y: 0.095, width: 0.28, height: 0.065),
                categories: [.thyroid]
            ),
            // ── Chest ─────────────────────────────────────────────────────
            // Heart sits beside the otherwise-unused lungs illustration —
            // both live in the chest, and cardio + respiratory markers are
            // commonly read together.
            BodyRegion(
                id: "lipids_cbc",
                label: "Heart & Blood",
                systemImage: "heart.fill",
                primaryOrganImage: "OrganHeart",
                secondaryOrganImage: "OrganLungs",
                hitRect: CGRect(x: 0.22, y: 0.165, width: 0.56, height: 0.14),
                categories: [.lipids, .cbc]
            ),
            // ── Upper abdomen ────────────────────────────────────────────
            // Liver sits under the right rib cage, which appears on the
            // *left* side of a front-facing figure.
            BodyRegion(
                id: "liver",
                label: "Liver",
                systemImage: "drop.fill",
                primaryOrganImage: "OrganLiver",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.20, y: 0.31, width: 0.29, height: 0.10),
                categories: [.liver]
            ),
            // Metabolism (glucose, insulin) is driven by the gut/pancreas —
            // shares the digestive illustration with Nutrients below until a
            // dedicated pancreas image is added.
            BodyRegion(
                id: "metabolic",
                label: "Metabolism",
                systemImage: "bolt.fill",
                primaryOrganImage: "OrganDigestive",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.51, y: 0.31, width: 0.29, height: 0.10),
                categories: [.metabolic]
            ),
            // ── Mid abdomen ──────────────────────────────────────────────
            BodyRegion(
                id: "renal",
                label: "Kidneys",
                systemImage: "circle.hexagongrid.fill",
                primaryOrganImage: "OrganKidneys",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.18, y: 0.42, width: 0.31, height: 0.10),
                categories: [.renal]
            ),
            // Nutrient absorption happens along the gut, so it shares the
            // digestive illustration with Metabolism above.
            BodyRegion(
                id: "nutrients",
                label: "Nutrients",
                systemImage: "leaf.fill",
                primaryOrganImage: "OrganDigestive",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.51, y: 0.42, width: 0.31, height: 0.10),
                categories: [.nutrients]
            ),
            // ── Lower abdomen / pelvis ───────────────────────────────────
            // Electrolyte balance is regulated by the kidneys, so it shares
            // the kidneys illustration until a dedicated adrenal/muscular
            // image is added.
            BodyRegion(
                id: "electrolytes",
                label: "Electrolytes",
                systemImage: "bolt.heart.fill",
                primaryOrganImage: "OrganKidneys",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.18, y: 0.53, width: 0.31, height: 0.09),
                categories: [.electrolytes]
            ),
            // No dedicated organ illustration yet — OrganDetailView falls
            // back to a large systemImage glyph for this region.
            BodyRegion(
                id: "other",
                label: "Other",
                systemImage: "ellipsis.circle.fill",
                primaryOrganImage: "",
                secondaryOrganImage: nil,
                hitRect: CGRect(x: 0.51, y: 0.53, width: 0.31, height: 0.09),
                categories: [.other]
            ),
        ]
    }
}
