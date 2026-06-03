import Biomarkers
import Core
import Foundation
import Observation

/// Body-region grouping shown on the Body Map.
struct BodyRegion: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    /// Relative position within the body figure (0–1, origin = top-left).
    let relativeX: Double
    let relativeY: Double
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
    private(set) var regions: [BodyRegion] = BodyMapViewModel.makeRegions()
    private(set) var isLoading = false
    var errorMessage: String?

    private let biomarkersRepo: BiomarkersRepository

    init(biomarkersRepo: BiomarkersRepository) {
        self.biomarkersRepo = biomarkersRepo
    }

    func load() async {
        // Reuse already-loaded data if available to avoid a redundant network hit.
        if biomarkersRepo.results.isEmpty {
            isLoading = true
            await biomarkersRepo.loadResults()
            isLoading = false
            if let err = biomarkersRepo.error {
                errorMessage = err.localizedDescription
            }
        }
        distribute(biomarkersRepo.results)
    }

    private func distribute(_ results: [BiomarkerWithSeries]) {
        var updated = regions
        for i in updated.indices {
            updated[i].items = results.filter { item in
                updated[i].categories.contains(biomarkerCategory(for: item.biomarker.nameNo))
            }
        }
        regions = updated
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
                categories: [.thyroid]
            ),
            BodyRegion(
                id: "lipids_cbc",
                label: "Heart & Blood",
                systemImage: "heart.fill",
                relativeX: 0.36,
                relativeY: 0.285,
                categories: [.lipids, .cbc]
            ),
            BodyRegion(
                id: "liver",
                label: "Liver",
                systemImage: "drop.fill",
                relativeX: 0.64,
                relativeY: 0.345,
                categories: [.liver]
            ),
            BodyRegion(
                id: "metabolic",
                label: "Metabolism",
                systemImage: "bolt.fill",
                relativeX: 0.50,
                relativeY: 0.41,
                categories: [.metabolic]
            ),
            BodyRegion(
                id: "renal",
                label: "Kidneys",
                systemImage: "circle.hexagongrid.fill",
                relativeX: 0.50,
                relativeY: 0.48,
                categories: [.renal]
            ),
            BodyRegion(
                id: "nutrients",
                label: "Nutrients",
                systemImage: "leaf.fill",
                relativeX: 0.24,
                relativeY: 0.38,
                categories: [.nutrients]
            ),
            BodyRegion(
                id: "electrolytes",
                label: "Electrolytes",
                systemImage: "bolt.heart.fill",
                relativeX: 0.76,
                relativeY: 0.46,
                categories: [.electrolytes]
            ),
            BodyRegion(
                id: "other",
                label: "Other",
                systemImage: "ellipsis.circle.fill",
                relativeX: 0.50,
                relativeY: 0.82,
                categories: [.other]
            ),
        ]
    }
}
