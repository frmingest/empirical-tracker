import Biomarkers
import Core
import SwiftUI

/// Geometry shared by every report page. A4 in points (EU clinic standard).
enum ReportLayout {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 36
    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
}

// MARK: - Page chrome

/// Wraps page content with consistent margins, a white (print-safe) background,
/// a forced light appearance, and a footer carrying the disclaimer + page number.
struct ReportPageContainer<Content: View>: View {
    let pageNumber: Int
    let totalPages: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ReportFooter(pageNumber: pageNumber, totalPages: totalPages)
        }
        .padding(ReportLayout.margin)
        .frame(width: ReportLayout.pageSize.width, height: ReportLayout.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

private struct ReportFooter: View {
    let pageNumber: Int
    let totalPages: Int

    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 0.5)
            HStack {
                Text("Decision-support, not medical advice.")
                    .font(.labelMedium)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                Text("Page \(pageNumber) of \(totalPages)")
                    .font(.labelMedium)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Cover page

struct ReportCoverContent: View {
    let meta: ReportMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            masthead
            Spacer().frame(height: 28)
            summaryCard
            Spacer().frame(height: 20)
            disclaimerCard
            Spacer()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headlineMedium)
                    .foregroundStyle(Color.accent)
                Text("Empirical Tracker")
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Biomarker Report")
                .font(.displayLarge)
                .foregroundStyle(Color.textPrimary)

            Text(subtitle)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            Rectangle()
                .fill(Color.accent)
                .frame(width: 64, height: 3)
                .padding(.top, 4)
        }
    }

    private var subtitle: String {
        "Generated \(fmtDateLong(meta.generatedAt)) · \(meta.contentMode.title)"
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let patient = meta.patientLabel {
                summaryRow(label: "Prepared for", value: patient)
            }
            summaryRow(label: "Period covered", value: periodText)

            Rectangle().fill(Color.borderSubtle).frame(height: 0.5)

            HStack(spacing: 0) {
                statTile(value: "\(meta.totalMarkers)", label: "Markers", color: .textPrimary)
                statDivider
                statTile(value: "\(meta.inRangeCount)", label: "In range", color: .inRange)
                statDivider
                statTile(value: "\(meta.outOfRangeCount)", label: "Out of range", color: .outRange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderCard, lineWidth: 1)
        )
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.labelMedium)
                .foregroundStyle(Color.textMuted)
            Spacer()
            Text(value)
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.numericLarge)
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.labelMedium)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.borderSubtle).frame(width: 0.5, height: 36)
    }

    private var periodText: String {
        guard let earliest = meta.earliestTest, let latest = meta.latestTest else {
            return "—"
        }
        if Calendar.current.isDate(earliest, inSameDayAs: latest) {
            return fmtDateShort(latest)
        }
        return "\(fmtDateShort(earliest)) – \(fmtDateShort(latest))"
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.bodyMedium)
                .foregroundStyle(Color.accent)
            Text(Self.disclaimer)
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static let disclaimer =
        "This report is generated by Empirical Tracker for personal tracking and "
        + "decision-support only. It is not a medical diagnosis and not a substitute "
        + "for professional medical advice. Reference ranges are taken from the source "
        + "laboratory report and may vary between laboratories. Any trends shown are "
        + "visual correlations only and do not imply causation."
}

// MARK: - Latest values page

struct ReportLatestContent: View {
    let page: LatestPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(page.blocks) { block in
                categoryBlock(block)
            }
            Spacer(minLength: 0)
        }
    }

    private func categoryBlock(_ block: LatestCategoryBlock) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(block.category.displayName)
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
                if block.continued {
                    Text("(continued)")
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.bottom, 6)

            headerRow
            Rectangle().fill(Color.borderCard).frame(height: 0.5)

            ForEach(Array(block.markers.enumerated()), id: \.element.id) { index, marker in
                markerRow(marker)
                    .background(index.isMultiple(of: 2) ? Color.clear : Color.bgElevated.opacity(0.5))
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            columnText("Marker", weight: Columns.marker, align: .leading, header: true)
            columnText("Latest", weight: Columns.value, align: .trailing, header: true)
            columnText("Reference", weight: Columns.reference, align: .leading, header: true)
            columnText("Date", weight: Columns.date, align: .leading, header: true)
            columnText("Status", weight: Columns.status, align: .trailing, header: true)
        }
        .padding(.vertical, 5)
    }

    private func markerRow(_ marker: BiomarkerWithSeries) -> some View {
        let info = marker.biomarker
        let latest = marker.latestResult
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(shortBiomarkerLabel(info.nameEn ?? info.nameNo))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let nameEn = info.nameEn, nameEn != info.nameNo {
                    Text(info.nameNo)
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: ReportLayout.contentWidth * Columns.marker, alignment: .leading)

            columnText(latest.map { ReportFormatting.valueWithUnit($0.value, unit: info.unit) } ?? "—",
                       weight: Columns.value, align: .trailing, mono: true)
            columnText(ReportFormatting.reference(info), weight: Columns.reference, align: .leading)
            columnText(latest.map { fmtDateShort($0.testedAt) } ?? "—", weight: Columns.date, align: .leading)

            HStack {
                Spacer(minLength: 0)
                StatusBadgeView(status: ReportFormatting.badgeStatus(for: marker), compact: true)
            }
            .frame(width: ReportLayout.contentWidth * Columns.status, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    private func columnText(_ text: String, weight: CGFloat, align: Alignment, header: Bool = false, mono: Bool = false) -> some View {
        Text(text)
            .font(header ? .labelMedium : (mono ? .numericSmall : .bodySmall))
            .foregroundStyle(header ? Color.textMuted : Color.textPrimary)
            .lineLimit(1)
            .frame(width: ReportLayout.contentWidth * weight,
                   alignment: align == .trailing ? .trailing : .leading)
    }

    private enum Columns {
        static let marker: CGFloat = 0.30
        static let value: CGFloat = 0.18
        static let reference: CGFloat = 0.20
        static let date: CGFloat = 0.14
        static let status: CGFloat = 0.14
    }
}

// MARK: - Trend chart page

struct ReportChartContent: View {
    let page: ChartPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(page.markers) { marker in
                chartCard(marker)
            }
            Spacer(minLength: 0)
        }
    }

    private func chartCard(_ marker: BiomarkerWithSeries) -> some View {
        let info = marker.biomarker
        let latest = marker.latestResult
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.displayName)
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text("Reference: \(ReportFormatting.reference(info))")
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                }
                Spacer()
                if let latest {
                    HStack(spacing: 8) {
                        Text(ReportFormatting.valueWithUnit(latest.value, unit: info.unit))
                            .font(.numericMedium)
                            .foregroundStyle(Color.textPrimary)
                        StatusBadgeView(status: ReportFormatting.badgeStatus(for: marker), compact: true)
                    }
                }
            }

            BiomarkerTrendChart(marker: marker)
                .frame(height: 250)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.borderCard, lineWidth: 1)
        )
    }
}
