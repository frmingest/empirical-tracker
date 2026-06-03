import Biomarkers
import Core
import SwiftUI

/// Lets the user pick categories and/or individual markers, choose between
/// latest values and trend graphs, then generate a PDF and share it (e.g. by
/// email) with a clinician. Fulfils the Sprint 6 "doctor PDF report".
struct ReportShareSheet: View {
    let results: [BiomarkerWithSeries]
    let patientEmail: String?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ReportShareViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    content(vm)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Share report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .task {
            if viewModel == nil {
                viewModel = ReportShareViewModel(results: results, patientEmail: patientEmail)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: ReportShareViewModel) -> some View {
        if !vm.hasData {
            EmptyStateView(
                icon: "doc.text",
                title: "Nothing to share yet",
                message: "Import a blood test first, then you can export a report."
            )
        } else {
            List {
                contentModeSection(vm)
                ForEach(vm.groups) { group in
                    categorySection(vm, group: group)
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { bottomBar(vm) }
            .sheet(item: Binding(
                get: { vm.shareItem },
                set: { vm.shareItem = $0 }
            )) { item in
                ShareSheet(items: [item.url])
            }
            .alert("Report error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Content mode picker

    private func contentModeSection(_ vm: ReportShareViewModel) -> some View {
        Section {
            Picker("Include", selection: Binding(
                get: { vm.contentMode },
                set: { vm.contentMode = $0 }
            )) {
                ForEach(ReportContentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("What to include")
        } footer: {
            Text(modeFooter(vm.contentMode))
        }
    }

    private func modeFooter(_ mode: ReportContentMode) -> String {
        switch mode {
        case .latest: return "A table of the most recent value, reference range and status for each marker."
        case .graphs: return "A trend chart over time for each selected marker."
        case .both:   return "Latest-value tables followed by a trend chart for each selected marker."
        }
    }

    // MARK: - Category section

    private func categorySection(_ vm: ReportShareViewModel, group: ReportGroup) -> some View {
        Section {
            categoryHeaderRow(vm, group: group)
            if vm.expanded.contains(group.category) {
                ForEach(group.markers) { marker in
                    markerRow(vm, marker: marker)
                }
            }
        }
    }

    /// A normal list row (not a section header) so its buttons receive taps
    /// reliably: a select-all checkbox, the category title, and an expander.
    private func categoryHeaderRow(_ vm: ReportShareViewModel, group: ReportGroup) -> some View {
        HStack(spacing: 10) {
            Button {
                vm.toggleCategory(group)
            } label: {
                Image(systemName: categoryIcon(vm.selection(for: group)))
                    .font(.bodyLarge)
                    .foregroundStyle(vm.selection(for: group) == .none ? Color.textMuted : Color.accent)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.category.displayName)
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
                Text(selectionLabel(vm, group: group))
                    .font(.labelMedium)
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()

            Image(systemName: vm.expanded.contains(group.category) ? "chevron.up" : "chevron.down")
                .font(.labelLarge)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { vm.toggleExpanded(group.category) }
        }
    }

    private func markerRow(_ vm: ReportShareViewModel, marker: BiomarkerWithSeries) -> some View {
        Button {
            vm.toggle(marker)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: vm.isSelected(marker) ? "checkmark.circle.fill" : "circle")
                    .font(.bodyLarge)
                    .foregroundStyle(vm.isSelected(marker) ? Color.accent : Color.textMuted)

                VStack(alignment: .leading, spacing: 1) {
                    Text(shortBiomarkerLabel(marker.biomarker.nameEn ?? marker.biomarker.nameNo))
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let latest = marker.latestResult {
                        Text(ReportFormatting.valueWithUnit(latest.value, unit: marker.biomarker.unit))
                            .font(.labelMedium)
                            .foregroundStyle(Color.textMuted)
                    }
                }

                Spacer()

                StatusBadgeView(status: ReportFormatting.badgeStatus(for: marker), compact: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    private func bottomBar(_ vm: ReportShareViewModel) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(vm.hasSelection ? "\(vm.selectedCount) result\(vm.selectedCount == 1 ? "" : "s") selected"
                                     : "No results selected")
                    .font(.labelLarge)
                    .foregroundStyle(vm.hasSelection ? Color.textSecondary : Color.outRange)
                Spacer()
                HStack(spacing: 12) {
                    Button("All") { vm.selectAll() }
                        .font(.labelLarge)
                        .foregroundStyle(Color.accent)
                    Button("None") { vm.selectNone() }
                        .font(.labelLarge)
                        .foregroundStyle(Color.accent)
                }
            }

            Button {
                Task { await vm.generate() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isGenerating {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(vm.isGenerating ? "Generating…" : "Create PDF")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.hasSelection ? Color.accent : Color.textMuted)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!vm.hasSelection || vm.isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ selection: ReportShareViewModel.CategorySelection) -> String {
        switch selection {
        case .all:     return "checkmark.circle.fill"
        case .partial: return "minus.circle.fill"
        case .none:    return "circle"
        }
    }

    private func selectionLabel(_ vm: ReportShareViewModel, group: ReportGroup) -> String {
        let selected = group.markers.filter { vm.isSelected($0) }.count
        return "\(selected) of \(group.markers.count) selected"
    }
}

// MARK: - Preview

#Preview {
    ReportShareSheet(
        results: MockData.biomarkerSeries,
        patientEmail: "patient@example.com"
    )
}
