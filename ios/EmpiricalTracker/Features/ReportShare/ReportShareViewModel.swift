import Biomarkers
import Core
import Foundation
import Observation

/// Drives the share sheet: tracks which markers are selected, the content mode,
/// and turns the selection into a shareable PDF.
@MainActor
@Observable
final class ReportShareViewModel {

    // MARK: - User selection

    var contentMode: ReportContentMode = .both
    /// `BiomarkerWithSeries.id` values currently included in the report.
    var selectedIDs: Set<String>
    /// Categories whose marker list is expanded in the picker.
    var expanded: Set<BiomarkerCategory> = []

    // MARK: - Generation state

    var isGenerating = false
    var shareItem: ReportShareItem?
    var errorMessage: String?

    // MARK: - Source data

    /// All categories with data, read once from the repository snapshot.
    let groups: [ReportGroup]
    private let patientLabel: String?

    init(results: [BiomarkerWithSeries], patientEmail: String?) {
        self.groups = groupedByCategory(results).map {
            ReportGroup(category: $0.category, markers: $0.items)
        }
        self.patientLabel = patientEmail
        // Default to everything selected — the user narrows down from there.
        self.selectedIDs = Set(results.map(\.id))
    }

    // MARK: - Derived selection

    var selectedGroups: [ReportGroup] {
        groups.compactMap { group in
            let markers = group.markers.filter { selectedIDs.contains($0.id) }
            return markers.isEmpty ? nil : ReportGroup(category: group.category, markers: markers)
        }
    }

    var selectedMarkers: [BiomarkerWithSeries] {
        selectedGroups.flatMap(\.markers)
    }

    var selectedCount: Int { selectedMarkers.count }
    var hasSelection: Bool { selectedCount > 0 }
    var hasData: Bool { !groups.isEmpty }

    // MARK: - Per-marker selection

    func isSelected(_ marker: BiomarkerWithSeries) -> Bool {
        selectedIDs.contains(marker.id)
    }

    func toggle(_ marker: BiomarkerWithSeries) {
        if selectedIDs.contains(marker.id) {
            selectedIDs.remove(marker.id)
        } else {
            selectedIDs.insert(marker.id)
        }
    }

    // MARK: - Per-category selection

    enum CategorySelection { case none, partial, all }

    func selection(for group: ReportGroup) -> CategorySelection {
        let selected = group.markers.filter { selectedIDs.contains($0.id) }.count
        if selected == 0 { return .none }
        if selected == group.markers.count { return .all }
        return .partial
    }

    func toggleCategory(_ group: ReportGroup) {
        let ids = group.markers.map(\.id)
        if selection(for: group) == .all {
            selectedIDs.subtract(ids)
        } else {
            selectedIDs.formUnion(ids)
        }
    }

    func toggleExpanded(_ category: BiomarkerCategory) {
        if expanded.contains(category) {
            expanded.remove(category)
        } else {
            expanded.insert(category)
        }
    }

    // MARK: - Bulk selection

    func selectAll() { selectedIDs = Set(groups.flatMap(\.markers).map(\.id)) }
    func selectNone() { selectedIDs.removeAll() }

    // MARK: - Generation

    func generate() async {
        guard hasSelection else { return }
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        let meta = makeMeta()
        let latestGroups = selectedGroups
        let chartMarkers = selectedMarkers

        // Yield so the spinner can paint before the (synchronous, main-actor)
        // ImageRenderer work begins.
        await Task.yield()

        if let url = ReportPDFRenderer.render(
            meta: meta,
            latestGroups: latestGroups,
            chartMarkers: chartMarkers
        ) {
            shareItem = ReportShareItem(url: url)
        } else {
            errorMessage = "Could not generate the report. Please try again."
        }
    }

    private func makeMeta() -> ReportMeta {
        let markers = selectedMarkers
        let dates = markers.flatMap { $0.series.map(\.testedAt) }
        let outOfRange = markers.filter { $0.latestResult?.inRange == false }.count
        let inRange = markers.filter { $0.latestResult?.inRange == true }.count
        return ReportMeta(
            patientLabel: patientLabel,
            generatedAt: Date(),
            earliestTest: dates.min(),
            latestTest: dates.max(),
            totalMarkers: markers.count,
            outOfRangeCount: outOfRange,
            inRangeCount: inRange,
            contentMode: contentMode
        )
    }
}
