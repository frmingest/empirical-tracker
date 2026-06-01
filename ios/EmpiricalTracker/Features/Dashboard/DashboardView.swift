import Biomarkers
import Core
import Auth
import SwiftUI

/// Home tab — faithful replica of the web dashboard.
/// Sprint 2 delivers the read path: live data, category grid, diet filter, flagged toggle.
/// Import action is wired in Sprint 4.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var viewModel: DashboardViewModel?
    @State private var customMarkerDraft: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: "Loading…")
                }
            }
            .navigationTitle("Dashboard")
            .toolbar { toolbarContent }
        }
        .task {
            // Initialise once; preserve local UI state across tab switches.
            if viewModel == nil {
                viewModel = DashboardViewModel(
                    biomarkersRepo: env.biomarkers,
                    accountRepo: env.account
                )
            }
            await viewModel?.load()
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(_ vm: DashboardViewModel) -> some View {
        if vm.isLoading && !vm.hasData {
            skeletonView
        } else if !vm.hasData {
            emptyState
        } else {
            scrollContent(vm)
        }
    }

    private func scrollContent(_ vm: DashboardViewModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Diet focus filter bar
                DietFilterView(currentFocus: vm.currentFocus) { focus in
                    if focus == .custom {
                        customMarkerDraft = vm.customMarkers
                        vm.isCustomPickerPresented = true
                    } else {
                        await vm.setFocus(focus)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Flagged-only toggle
                flaggedToggle(vm)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Category sections
                if vm.sections.isEmpty {
                    noResultsForFilter
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(vm.sections) { group in
                            CategorySectionView(group: group) { tapped in
                                // Sprint 3: push BiomarkerDetailView
                                _ = tapped
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .refreshable { await vm.load() }
        .sheet(isPresented: Binding(
            get: { vm.isCustomPickerPresented },
            set: { vm.isCustomPickerPresented = $0 }
        )) {
            CustomMarkerPickerSheet(
                allMarkerNames: vm.allMarkerNames,
                selected: $customMarkerDraft
            ) {
                await vm.setCustomMarkers(customMarkerDraft)
                await vm.setFocus(.custom)
            }
        }
    }

    // MARK: - Flagged toggle

    private func flaggedToggle(_ vm: DashboardViewModel) -> some View {
        Toggle(isOn: Binding(
            get: { vm.showFlaggedOnly },
            set: { vm.showFlaggedOnly = $0 }
        )) {
            Label("Out of range only", systemImage: "exclamationmark.circle")
                .font(.bodyMedium)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(Color.outRange)
    }

    // MARK: - Empty / skeleton states

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: "No data yet",
            message: "Import your first blood test to see your biomarkers here."
        )
    }

    private var noResultsForFilter: some View {
        EmptyStateView(
            icon: "line.3.horizontal.decrease.circle",
            title: "No markers for this filter",
            message: "Try a different diet focus or switch to All."
        )
        .frame(maxWidth: .infinity)
    }

    private var skeletonView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonSectionView()
                }
            }
            .padding(16)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // Sprint 4: ImportSheet trigger
            Button {
                // TODO Sprint 4: present ImportSheet
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .accessibilityLabel("Import blood test")
            }
            .foregroundStyle(Color.accent)
        }
    }
}

// MARK: - Skeleton loading placeholder

private struct SkeletonSectionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.borderCard)
                .frame(width: 100, height: 14)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.bgCard)
                        .frame(height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.borderCard, lineWidth: 1)
                        )
                        .shimmer()
                }
            }
        }
    }
}

// MARK: - Shimmer modifier

private extension View {
    func shimmer() -> some View {
        self.overlay(
            LinearGradient(
                colors: [.clear, Color.bgElevated.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}

// MARK: - Preview

#Preview("With mock data") {
    let env = AppEnvironment.preview()
    env.biomarkers.results = MockData.biomarkerSeries
    return DashboardView()
        .environment(env)
}

#Preview("Empty state") {
    DashboardView()
        .environment(AppEnvironment.preview())
}
