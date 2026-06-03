import Biomarkers
import Core
import SwiftUI
import UIKit

/// Renders the report into a multi-page, vector (text-selectable) PDF on disk.
///
/// Each page is a SwiftUI view rendered through `ImageRenderer` directly into a
/// shared `CGContext` PDF, so text and Swift Charts stay crisp at any zoom and
/// the file is small. Returns a temporary-directory URL ready to share.
@MainActor
enum ReportPDFRenderer {

    static func render(
        meta: ReportMeta,
        latestGroups: [ReportGroup],
        chartMarkers: [BiomarkerWithSeries]
    ) -> URL? {
        // 1. Build the ordered list of page contents.
        var contents: [ReportPageContent] = [.cover]
        if meta.contentMode.includesLatest {
            contents += ReportPaginator.latestPages(from: latestGroups).map(ReportPageContent.latest)
        }
        if meta.contentMode.includesGraphs {
            contents += ReportPaginator.chartPages(from: chartMarkers).map(ReportPageContent.charts)
        }
        let total = contents.count

        // 2. Open a single PDF context for all pages.
        let url = outputURL(generatedAt: meta.generatedAt)
        var mediaBox = CGRect(origin: .zero, size: ReportLayout.pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        // 3. Render each page into the context.
        for (index, content) in contents.enumerated() {
            let page = ReportPageContainer(pageNumber: index + 1, totalPages: total) {
                pageBody(content, meta: meta)
            }
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(ReportLayout.pageSize)
            renderer.render { _, drawInContext in
                pdf.beginPDFPage(nil)
                drawInContext(pdf)
                pdf.endPDFPage()
            }
        }

        pdf.closePDF()
        return url
    }

    @ViewBuilder
    private static func pageBody(_ content: ReportPageContent, meta: ReportMeta) -> some View {
        switch content {
        case .cover:
            ReportCoverContent(meta: meta)
        case .latest(let model):
            ReportLatestContent(page: model)
        case .charts(let model):
            ReportChartContent(page: model)
        }
    }

    private static func outputURL(generatedAt: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let stamp = formatter.string(from: generatedAt)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("Biomarker-Report-\(stamp).pdf")
    }
}
