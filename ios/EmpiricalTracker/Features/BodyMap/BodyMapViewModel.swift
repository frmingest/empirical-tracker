import Biomarkers
import Core
import Foundation
import Observation

/// Which margin a region's pin is parked in, beside the silhouette. The pin
/// floats in the open space on this side and a leader line connects it back to
/// the region's anatomical anchor on the body.
enum BodySide {
    case left
    case right
}

/// Body-region grouping shown on the Body Map.
struct BodyRegion: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    /// Anatomical anchor within the body figure (0–1, origin = top-left). This
    /// is where the leader line points; the pin itself is parked in the margin.
    let relativeX: Double
    let relativeY: Double
    /// Margin the pin is parked in. Regions are split roughly evenly between the
    /// two sides so neither column gets crowded.
    let side: BodySide
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
            BodyRegion(
                id: "thyroid",
                label: "Thyroid",
                systemImage: "waveform.path.ecg",
                relativeX: 0.50,
                relativeY: 0.155,
                side: .left,
                categories: [.thyroid]
            ),
            BodyRegion(
                id: "lipids_cbc",
                label: "Heart & Blood",
                systemImage: "heart.fill",
                relativeX: 0.36,
                relativeY: 0.285,
                side: .left,
                categories: [.lipids, .cbc]
            ),
            BodyRegion(
                id: "liver",
                label: "Liver",
                systemImage: "drop.fill",
                relativeX: 0.64,
                relativeY: 0.345,
                side: .right,
                categories: [.liver]
            ),
            BodyRegion(
                id: "metabolic",
                label: "Metabolism",
                systemImage: "bolt.fill",
                relativeX: 0.50,
                relativeY: 0.41,
                side: .left,
                categories: [.metabolic]
            ),
            BodyRegion(
                id: "renal",
                label: "Kidneys",
                systemImage: "circle.hexagongrid.fill",
                relativeX: 0.50,
                relativeY: 0.48,
                side: .right,
                categories: [.renal]
            ),
            BodyRegion(
                id: "nutrients",
                label: "Nutrients",
                systemImage: "leaf.fill",
                relativeX: 0.24,
                relativeY: 0.38,
                side: .left,
                categories: [.nutrients]
            ),
            BodyRegion(
                id: "electrolytes",
                label: "Electrolytes",
                systemImage: "bolt.heart.fill",
                relativeX: 0.76,
                relativeY: 0.46,
                side: .right,
                categories: [.electrolytes]
            ),
            BodyRegion(
                id: "other",
                label: "Other",
                systemImage: "ellipsis.circle.fill",
                relativeX: 0.50,
                relativeY: 0.82,
                side: .right,
                categories: [.other]
            ),
        ]
    }
}
