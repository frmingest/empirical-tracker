import Biomarkers
import Core
import Foundation
import SwiftUI

// MARK: - Content mode

/// What a shared report contains. The user picks one in the share sheet.
/// Mirrors the Sprint 6 "doctor PDF report" scope: latest values and/or trends.
enum ReportContentMode: String, CaseIterable, Identifiable, Sendable {
    case latest
    case graphs
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: return "Latest values"
        case .graphs: return "Trend graphs"
        case .both:   return "Both"
        }
    }

    var includesLatest: Bool { self != .graphs }
    var includesGraphs: Bool { self != .latest }
}

// MARK: - App-side group type

/// A category + its markers, owned by the app target.
///
/// `Biomarkers.BiomarkerGroup` only has an `internal` memberwise initialiser,
/// so we can read it (via `groupedByCategory`) but cannot construct filtered
/// copies of it. This light-weight mirror lets the report build its own
/// selection-filtered groups.
struct ReportGroup: Identifiable {
    let category: BiomarkerCategory
    let markers: [BiomarkerWithSeries]
    var id: String { category.rawValue }
}

// MARK: - Report metadata (cover page)

/// Everything the cover page needs, computed once at generation time.
struct ReportMeta {
    let patientLabel: String?
    let generatedAt: Date
    let earliestTest: Date?
    let latestTest: Date?
    let totalMarkers: Int
    let outOfRangeCount: Int
    let inRangeCount: Int
    let contentMode: ReportContentMode
}

// MARK: - Shared formatting

/// Centralised, print-friendly formatting reused across every report page so
/// values, references, and status badges match the in-app screens exactly.
enum ReportFormatting {
    /// Matches `BiomarkerCardView.formattedValue` so the PDF and the app agree.
    static func value(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }

    static func valueWithUnit(_ v: Double, unit: String?) -> String {
        let base = value(v)
        if let unit, !unit.isEmpty { return "\(base) \(unit)" }
        return base
    }

    /// Reference range as shown in `BiomarkerDetailView` ("12.0–16.0 g/dL").
    static func reference(_ info: BiomarkerInfo) -> String {
        let raw = info.refRangeRaw.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return "—" }
        if let unit = info.unit, !unit.isEmpty { return "\(raw) \(unit)" }
        return raw
    }

    static func badgeStatus(for marker: BiomarkerWithSeries) -> StatusBadgeView.Status {
        switch MarkerSignals.assessment(for: marker) {
        case .inRange:    return .inRange
        case .outOfRange: return .outOfRange
        case .watch:      return .watch
        case .unknown:    return .unknown
        }
    }
}

// MARK: - Share item

/// Wraps the generated PDF URL so it can drive a `.sheet(item:)`.
struct ReportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Pagination

/// Fixed-size PDF pages cannot scroll, so report content is split into pages
/// up front. These models describe one page's worth of content.
struct LatestCategoryBlock: Identifiable {
    let category: BiomarkerCategory
    let markers: [BiomarkerWithSeries]
    /// `true` when a long category spills onto a second page ("… continued").
    let continued: Bool
    var id: String { category.rawValue + (continued ? "-cont" : "") }
}

struct LatestPageModel {
    let blocks: [LatestCategoryBlock]
}

struct ChartPageModel {
    let markers: [BiomarkerWithSeries]
}

/// One physical page of the report, in render order.
enum ReportPageContent {
    case cover
    case latest(LatestPageModel)
    case charts(ChartPageModel)
}

/// Splits selected markers into fixed-height pages using an estimated point
/// budget (A4 content height), so tables and charts never overflow a page.
enum ReportPaginator {
    /// Usable vertical space per page after margins and the footer (A4 ≈ 770pt).
    static let pageContentHeight: CGFloat = 720
    /// Category title + column-header + divider + inter-block spacing.
    static let categoryOverhead: CGFloat = 80
    static let blockSpacing: CGFloat = 18
    static let markerRowHeight: CGFloat = 30
    /// Trend charts per graph page (header + 250pt chart ≈ 340pt each).
    static let chartsPerPage = 2

    static func latestPages(from groups: [ReportGroup]) -> [LatestPageModel] {
        var pages: [LatestPageModel] = []
        var current: [LatestCategoryBlock] = []
        var used: CGFloat = 0

        func flush() {
            guard !current.isEmpty else { return }
            pages.append(LatestPageModel(blocks: current))
            current = []
            used = 0
        }

        for group in groups {
            var index = 0
            var continued = false
            while index < group.markers.count {
                var overhead = categoryOverhead + (current.isEmpty ? 0 : blockSpacing)
                // Start a fresh page if even the header + one row won't fit.
                if used + overhead + markerRowHeight > pageContentHeight {
                    flush()
                    overhead = categoryOverhead
                }
                let available = pageContentHeight - used - overhead
                let maxRows = max(1, Int(available / markerRowHeight))
                let take = min(maxRows, group.markers.count - index)
                let slice = Array(group.markers[index..<index + take])
                current.append(
                    LatestCategoryBlock(category: group.category, markers: slice, continued: continued)
                )
                used += overhead + CGFloat(take) * markerRowHeight
                index += take
                continued = true
                if used >= pageContentHeight - markerRowHeight { flush() }
            }
        }
        flush()
        return pages
    }

    static func chartPages(from markers: [BiomarkerWithSeries]) -> [ChartPageModel] {
        stride(from: 0, to: markers.count, by: chartsPerPage).map { start in
            ChartPageModel(markers: Array(markers[start..<min(start + chartsPerPage, markers.count)]))
        }
    }
}
