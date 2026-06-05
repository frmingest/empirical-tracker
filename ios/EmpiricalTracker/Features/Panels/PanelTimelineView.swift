import Biomarkers
import Core
import SwiftUI

/// Chronological list of all blood-draw panels.
/// Presented as a sheet from the dashboard toolbar.
/// Supports swipe-to-delete and a "Delete all" menu action with confirmation.
struct PanelTimelineView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PanelTimelineViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    LoadingView(message: "Loading panels…")
                }
            }
            .navigationTitle("Blood Test History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
        }
        .task {
            if viewModel == nil {
                viewModel = PanelTimelineViewModel(biomarkersRepo: env.biomarkers)
            }
            await viewModel?.load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: PanelTimelineViewModel) -> some View {
        if vm.isLoading && vm.panels.isEmpty {
            LoadingView(message: "Loading panels…")
        } else if vm.panels.isEmpty {
            EmptyStateView(
                icon: "calendar.badge.clock",
                title: "No blood tests yet",
                message: "Import a .xlsx file from your laboratory to see your history here."
            )
        } else {
            panelList(vm)
        }
    }

    private func panelList(_ vm: PanelTimelineViewModel) -> some View {
        List {
            ForEach(vm.panels) { panel in
                PanelCardView(
                    panel: panel,
                    flaggedMarkers: vm.flaggedMarkerNames(for: panel)
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.bgBase)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        vm.confirmDelete(panel)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.bgBase)
        .refreshable { await vm.load() }
        // Single-panel delete confirmation
        .confirmationDialog(
            "Delete this panel?",
            isPresented: Binding(
                get: { vm.panelPendingDelete != nil },
                set: { if !$0 { vm.cancelDelete() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await vm.executeDelete() }
            }
            Button("Cancel", role: .cancel) { vm.cancelDelete() }
        } message: {
            if let p = vm.panelPendingDelete {
                Text("This will permanently remove the \(formattedDate(p.testedAt)) panel and all its results. This cannot be undone.")
            }
        }
        // Delete-all confirmation
        .confirmationDialog(
            "Delete all panels?",
            isPresented: Binding(
                get: { vm.isDeleteAllConfirmationPresented },
                set: { vm.isDeleteAllConfirmationPresented = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await vm.executeDeleteAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all \(vm.panels.count) panels and every result they contain. This cannot be undone.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Explicit way back to the dashboard — the sheet is otherwise only
        // dismissible by swiping down, which isn't discoverable.
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
                .foregroundStyle(Color.accent)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let vm = viewModel, !vm.panels.isEmpty {
                Menu {
                    Button(role: .destructive) {
                        vm.isDeleteAllConfirmationPresented = true
                    } label: {
                        Label("Delete all panels", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.accent)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Preview

#Preview("With panels") {
    let env = AppEnvironment.preview()
    env.biomarkers.panels = [
        Panel(id: "p1", testedAt: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
              source: "xlsx", resultCount: 18, inRangeCount: 15, outRangeCount: 3),
        Panel(id: "p2", testedAt: Calendar.current.date(byAdding: .day, value: -90, to: Date())!,
              source: "xlsx", resultCount: 16, inRangeCount: 16, outRangeCount: 0),
    ]
    env.biomarkers.results = MockData.biomarkerSeries
    return PanelTimelineView()
        .environment(env)
}

#Preview("Empty") {
    PanelTimelineView()
        .environment(AppEnvironment.preview())
}
