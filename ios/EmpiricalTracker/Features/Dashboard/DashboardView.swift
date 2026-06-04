import Biomarkers
import Core
import AppAuth
import SwiftUI

/// Home tab — faithful replica of the web dashboard.
/// Sprint 2 delivers the read path: live data, category grid, diet filter, flagged toggle.
/// Import action is wired in Sprint 4.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var viewModel: DashboardViewModel?
    @State private var customMarkerDraft: Set<String> = []

    // Sprint 4 — import & panel timeline state
    @State private var importViewModel: ImportViewModel?
    @State private var isPanelTimelinePresented = false

    // Sprint 6 — share biomarker report as PDF
    @State private var isReportSharePresented = false

    // Sprint 3 — marker drill-down
    @State private var selectedMarker: BiomarkerWithSeries?
    // Category graph view — pushed when a category header is tapped.
    @State private var selectedCategory: BiomarkerCategory?

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
            .navigationDestination(item: $selectedMarker) { marker in
                BiomarkerDetailView(initialMarker: marker)
            }
            .navigationDestination(item: $selectedCategory) { category in
                CategoryGraphsView(initialCategory: category) { marker in
                    selectedMarker = marker
                }
            }
        }
        .task {
            // Initialise once; preserve local UI state across tab switches.
            if viewModel == nil {
                viewModel = DashboardViewModel(
                    biomarkersRepo: env.biomarkers,
                    accountRepo: env.account
                )
            }
            if importViewModel == nil {
                importViewModel = ImportViewModel(
                    biomarkersRepo: env.biomarkers,
                    importService: env.biomarkersImport
                )
            }
            await viewModel?.load()
        }
        // Present import sheet
        .sheet(isPresented: Binding(
            get: { importViewModel?.isPresented ?? false },
            set: { importViewModel?.isPresented = $0 }
        )) {
            if let ivm = importViewModel {
                ImportSheetView(viewModel: ivm)
            }
        }
        // Present panel timeline
        .sheet(isPresented: $isPanelTimelinePresented) {
            PanelTimelineView()
        }
        // Present share-report sheet
        .sheet(isPresented: $isReportSharePresented) {
            ReportShareSheet(
                results: env.biomarkers.results,
                patientEmail: env.authStore.email
            )
        }
        // Handle .xlsx files opened from Files / Mail / AirDrop
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "xlsx" else { return }
            if importViewModel == nil {
                importViewModel = ImportViewModel(
                    biomarkersRepo: env.biomarkers,
                    importService: env.biomarkersImport
                )
            }
            importViewModel?.pendingFileURL = url
            importViewModel?.isPresented = true
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
                .padding(.bottom, 8)

                // Flagged-only toggle
                flaggedToggle(vm)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Category sections
                if vm.sections.isEmpty {
                    noResultsForFilter
                        .padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(vm.sections) { group in
                            CategorySectionView(
                                group: group,
                                onTapCard: { tapped in selectedMarker = tapped },
                                onTapHeader: { category in selectedCategory = category }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.bgBase)
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
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)
        }
        .tint(Color.outRange)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
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
        // History button
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isPanelTimelinePresented = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .accessibilityLabel("Blood test history")
            }
            .foregroundStyle(Color.accent)
        }
        // Share-report button
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isReportSharePresented = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityLabel("Share report")
            }
            .foregroundStyle(Color.accent)
            .disabled(viewModel?.hasData != true)
        }
        // Import button
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                importViewModel?.reset()
                importViewModel?.isPresented = true
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
