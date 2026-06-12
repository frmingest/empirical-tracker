import Biomarkers
import Core
import AppAuth
import SwiftUI

// MARK: - View mode

enum DashboardViewMode: String, CaseIterable {
    case grid    = "grid"
    case bodyMap = "bodyMap"

    var icon: String {
        switch self {
        case .grid:    return "square.grid.2x2"
        case .bodyMap: return "figure.stand"
        }
    }

    var label: String {
        switch self {
        case .grid:    return String(localized: "dashboard.mode.grid")
        case .bodyMap: return String(localized: "dashboard.mode.bodyMap")
        }
    }
}

/// Body tab — faithful replica of the web dashboard.
/// Sprint 2 delivers the read path: live data, category grid, diet filter, flagged toggle.
/// Import action is wired in Sprint 4.
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var viewModel: DashboardViewModel?
    @State private var customMarkerDraft: Set<String> = []
    @State private var dashboardMode: DashboardViewMode = .bodyMap

    // Sprint 4 — import state
    @State private var importViewModel: ImportViewModel?

    // Sprint 6 — share biomarker report as PDF
    @State private var isReportSharePresented = false

    // Sample-data explore mode, offered from the empty state so a new user can see
    // a populated dashboard before their first lab import.
    @State private var isSampleExplorePresented = false

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
                    LoadingView(message: String(localized: "common.loading"))
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
        // Present share-report sheet
        .sheet(isPresented: $isReportSharePresented) {
            ReportShareSheet(
                results: env.biomarkers.results,
                patientEmail: env.authStore.email
            )
        }
        // Present sample-data explore mode (offered from the empty state)
        .fullScreenCover(isPresented: $isSampleExplorePresented) {
            SampleDataExploreView()
        }
        // Handle .xlsx files opened from Files / Mail / AirDrop
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "xlsx", !env.isSampleData else { return }
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
        switch dashboardMode {
        case .grid:
            if vm.isLoading && !vm.hasData {
                skeletonView
            } else if !vm.hasData {
                emptyState
            } else {
                scrollContent(vm)
            }
        case .bodyMap:
            // An all-grey silhouette gives a new user no next step — show the
            // directive empty state (import / explore sample data) instead.
            if !vm.hasData && !vm.isLoading {
                emptyState
            } else {
                DashboardBodyMapView(
                    onSelectCategory: { category in selectedCategory = category },
                    onSelectMarker:   { marker   in selectedMarker   = marker   }
                )
            }
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
        VStack(spacing: 0) {
            EmptyStateView(
                icon: "tray",
                title: String(localized: "dashboard.emptyTitle"),
                message: String(localized: "dashboard.emptyMessage"),
                action: .init(label: String(localized: "dashboard.empty.import")) {
                    importViewModel?.reset()
                    importViewModel?.isPresented = true
                }
            )
            if !env.isSampleData {
                Button {
                    isSampleExplorePresented = true
                } label: {
                    Label(String(localized: "dashboard.empty.sample"), systemImage: "sparkles")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.accent)
                }
                .padding(.bottom, 32)
            }
        }
        .background(Color.bgBase)
    }

    private var noResultsForFilter: some View {
        EmptyStateView(
            icon: "line.3.horizontal.decrease.circle",
            title: String(localized: "dashboard.noFilter.title"),
            message: String(localized: "dashboard.noFilter.message")
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
        // View mode toggle
        ToolbarItem(placement: .topBarLeading) {
            ViewModeToggle(mode: $dashboardMode)
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
        // Import button (hidden in sample mode — there is no account to import into)
        if !env.isSampleData {
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

// MARK: - View mode toggle

private struct ViewModeToggle: View {
    @Binding var mode: DashboardViewMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DashboardViewMode.allCases, id: \.rawValue) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    Image(systemName: m.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 28)
                        .background(
                            mode == m
                                ? Color.accent.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .foregroundStyle(mode == m ? Color.accent : Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.label)
            }
        }
        .padding(3)
        .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 0.5)
        )
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
