import Core
import SwiftUI

/// Full-screen "browse with sample data" mode.
///
/// Hosts the real Dashboard surface (body map, biomarker grid, detail charts with
/// diet-event overlays) against `AppEnvironment.sampleData()` — a seeded, local-only
/// world — so a brand-new user sees what the app looks like *after* a lab import
/// without creating data or touching the network. Reachable from the auth screen
/// and from the dashboard's empty state.
struct SampleDataExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sampleEnv = AppEnvironment.sampleData()

    var body: some View {
        VStack(spacing: 0) {
            banner
            DashboardView()
                .environment(sampleEnv)
        }
        .background(Color.bgBase)
    }

    /// Persistent strip so sample mode is never mistaken for the user's own data.
    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.bodyMedium)
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "sample.banner.title"))
                    .font(.labelLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: "sample.banner.message"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(String(localized: "sample.done")) { dismiss() }
                .font(.headlineSmall)
                .foregroundStyle(Color.accent)
                .accessibilityLabel(String(localized: "sample.done.a11y"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accent.opacity(0.10))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

#Preview {
    SampleDataExploreView()
}
