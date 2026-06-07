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
    private(set) var regions: [BodyRegion] = BodyMapViewModel.makeRegions()
    private(set) var isLoading = false
    private(set) var filterYear: Int? = nil
    var errorMessage: String?

    private let biomarkersRepo: BiomarkersRepository

    init(biomarkersRepo: BiomarkersRepository) {
        self.biomarkersRepo = biomarkersRepo
    }

    /// Years that appear in the loaded data, newest first. Empty when no data.
    var availableYears: [Int] {
        let cal = Calendar.current
        let years = Set(
            biomarkersRepo.results
                .flatMap { $0.series }
                .map { cal.component(.year, from: $0.testedAt) }
        )
        return years.sorted(by: >)
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

    func setFilterYear(_ year: Int?) {
        filterYear = year
        distribute(biomarkersRepo.results)
    }

    private func distribute(_ results: [BiomarkerWithSeries]) {
        let cal = Calendar.current
        var updated = regions
        for i in updated.indices {
            let cats = updated[i].categories
            updated[i].items = results
                .filter { cats.contains(biomarkerCategory(for: $0.biomarker.nameNo)) }
                .compactMap { item -> BiomarkerWithSeries? in
                    guard let year = filterYear else { return item }
                    let filtered = item.series.filter { cal.component(.year, from: $0.testedAt) == year }
                    return filtered.isEmpty ? nil : BiomarkerWithSeries(biomarker: item.biomarker, series: filtered)
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
