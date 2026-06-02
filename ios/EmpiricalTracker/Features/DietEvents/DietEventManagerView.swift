import Core
import DietEvents
import SwiftUI

/// Full-screen list of all diet events with add / delete.
/// Accessed from Settings → Diet Events.
/// Sprint 5: full CRUD parity with the web `/diet-events` manager.
struct DietEventManagerView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel: DietEventViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                content(vm)
            } else {
                LoadingView(message: String(localized: "diet_events.loading"))
            }
        }
        .navigationTitle(String(localized: "diet_events.title"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if viewModel == nil {
                viewModel = DietEventViewModel(repo: env.dietEvents)
            }
            await viewModel?.load()
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.isFormPresented ?? false },
            set: { viewModel?.isFormPresented = $0 }
        )) {
            if let vm = viewModel {
                DietEventFormSheet(viewModel: vm)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel?.resetForm()
                    viewModel?.isFormPresented = true
                } label: {
                    Image(systemName: "plus")
                        .accessibilityLabel(String(localized: "diet_events.add"))
                }
                .foregroundStyle(Color.accent)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ vm: DietEventViewModel) -> some View {
        if vm.isLoading && vm.events.isEmpty {
            LoadingView(message: String(localized: "diet_events.loading"))
        } else if vm.events.isEmpty {
            emptyState
        } else {
            list(vm)
        }
    }

    private func list(_ vm: DietEventViewModel) -> some View {
        List {
            disclaimerRow
            ForEach(vm.events) { event in
                DietEventRow(event: event)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(id: event.id) }
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .alert(
            String(localized: "diet_events.error.title"),
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "calendar.badge.plus",
            title: String(localized: "diet_events.empty.title"),
            message: String(localized: "diet_events.empty.message")
        )
    }

    private var disclaimerRow: some View {
        Label {
            Text(String(localized: "diet_events.disclaimer"))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accent)
        }
        .listRowBackground(Color.bgCard)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Row

private struct DietEventRow: View {
    let event: DietEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind.icon)
                .foregroundStyle(event.kind.color)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Text(dateRangeText)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textSecondary)

                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(event.kind.displayName)
                .font(.labelSmall)
                .foregroundStyle(event.kind.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(event.kind.color.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var dateRangeText: String {
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        if let ended = event.endedOn {
            return "\(event.startedOn.formatted(fmt)) – \(ended.formatted(fmt))"
        }
        return event.startedOn.formatted(fmt)
    }

    private var accessibilityDescription: String {
        "\(event.label), \(event.kind.displayName), \(dateRangeText)"
    }
}

// MARK: - Kind color (view layer only)

extension DietEvent.Kind {
    var color: Color {
        switch self {
        case .diet:       return .inRange
        case .fast:       return .orange
        case .supplement: return .purple
        case .medication: return .outRange
        case .lifestyle:  return .accent
        case .other:      return .textMuted
        }
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    return NavigationStack {
        DietEventManagerView()
            .environment(env)
    }
}
