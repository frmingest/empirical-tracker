import Charts
import Core
import DietEvents
import SwiftUI

/// Reusable Swift Charts overlay for diet events.
/// Drop this inside any `Chart {}` block that spans a date-based x-axis.
///
/// Usage:
/// ```swift
/// Chart {
///     // … your main marks …
///     DietEventOverlayContent(events: overlappingEvents)
/// }
/// ```
struct DietEventOverlayContent: ChartContent {
    let events: [DietEvent]

    var body: some ChartContent {
        ForEach(events) { event in
            if let ended = event.endedOn {
                // Period — shaded rectangle spanning the range
                RectangleMark(
                    xStart: .value("Start", event.startedOn),
                    xEnd: .value("End", ended)
                )
                .foregroundStyle(event.kind.color.opacity(0.12))
                .accessibilityLabel(overlayLabel(event))
            } else {
                // Single-date point — dashed vertical rule
                RuleMark(x: .value("Date", event.startedOn))
                    .foregroundStyle(event.kind.color.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        eventAnnotation(event)
                    }
                    .accessibilityLabel(overlayLabel(event))
            }
        }
    }

    // MARK: - Annotation label

    @ViewBuilder
    private func eventAnnotation(_ event: DietEvent) -> some View {
        Text(event.label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(event.kind.color)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(event.kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }

    private func overlayLabel(_ event: DietEvent) -> String {
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated)
        if let ended = event.endedOn {
            return "\(event.label) \(event.startedOn.formatted(fmt)) to \(ended.formatted(fmt))"
        }
        return "\(event.label) \(event.startedOn.formatted(fmt))"
    }
}

/// Correlation disclaimer shown below any chart that renders diet-event overlays.
/// Mirrors the web's "visual correlation only, not causation" notice.
struct DietEventCorrelationDisclaimer: View {
    var body: some View {
        Label {
            Text(String(localized: "diet_events.disclaimer"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accent)
                .font(.bodySmall)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "diet_events.disclaimer"))
    }
}
