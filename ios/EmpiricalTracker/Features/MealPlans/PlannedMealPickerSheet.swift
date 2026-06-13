import Core
import SwiftUI

/// The schedule-a-meal sheet: pick a source, search (or scan a barcode), choose a
/// result, or fall back to free text. Mirrors `FoodSearchSheet` (Sprint 6) but
/// schedules onto the calendar rather than logging to the diary (ADR-012). Reuses
/// the diary's `BarcodeScannerView`, `FoodSourceBadge`, and `NutritionFormat`.
struct PlannedMealPickerSheet: View {
    @Bindable var viewModel: MealPlanViewModel

    @State private var selectedItem: FoodItem?
    /// Quantity to prefill when `selectedItem` was opened from a quick-add row's
    /// "edit" button; `nil` for an ordinary search result.
    @State private var quickEditQuantityG: Double?
    @State private var isFreeText = false
    @State private var isScanning = false
    @State private var scanMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                targetHeader
                searchField
                filterBar
                resultsList
            }
            .background(Color.bgBase)
            .navigationTitle(String(localized: "plan.schedule.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        viewModel.isPickerPresented = false
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                ScheduleMealSheet(viewModel: viewModel, item: item, initialQuantityG: quickEditQuantityG)
            }
            .sheet(isPresented: $isFreeText) {
                ScheduleMealSheet(viewModel: viewModel, freeTextName: trimmedQuery)
            }
            .fullScreenCover(isPresented: $isScanning) {
                BarcodeScannerView { result in
                    isScanning = false
                    handleScan(result)
                }
            }
            .alert(
                String(localized: "food.scan.not_found.title"),
                isPresented: Binding(
                    get: { scanMessage != nil },
                    set: { if !$0 { scanMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(scanMessage ?? "")
            }
        }
    }

    // MARK: - Target header (which day / meal we're scheduling onto)

    private var targetHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(Color.textMuted)
            Text(viewModel.addTargetDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Picker(String(localized: "food.log.meal"), selection: $viewModel.addTargetMeal) {
                ForEach(Meal.allCases) { m in
                    Text(m.localizedName).tag(m)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.accent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Filter bar (source chip + optional scan)

    /// Secondary controls beneath the search field: the source filter chip on the
    /// left, and — only for sources that carry barcodes — a compact scan button.
    private var filterBar: some View {
        HStack(spacing: 8) {
            FoodSourceFilterMenu(selection: $viewModel.selectedSource) {
                Task { await viewModel.searchNow() }
            }
            Spacer(minLength: 0)
            if viewModel.selectedSource.supportsBarcode {
                Button {
                    isScanning = true
                } label: {
                    Label(String(localized: "food.scan.button"), systemImage: "barcode.viewfinder")
                        .font(.bodyMedium)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textMuted)
            TextField(String(localized: "food.search.placeholder"), text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: viewModel.searchQuery) { viewModel.scheduleSearch() }
                .onSubmit { Task { await viewModel.searchNow() } }
            if viewModel.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        List {
            // Top-used products, one tap to schedule at the last-used quantity.
            if trimmedQuery.isEmpty && !viewModel.topFoods.isEmpty {
                Section(String(localized: "food.quickadd.title")) {
                    ForEach(viewModel.topFoods) { recent in
                        QuickAddRow(
                            recent: recent,
                            onAdd: { Task { await viewModel.quickSchedule(recent) } },
                            onEdit: {
                                quickEditQuantityG = recent.lastQuantityG
                                selectedItem = recent.asFoodItem()
                            }
                        )
                        .listRowBackground(Color.bgCard)
                    }
                }
            }

            ForEach(viewModel.searchResults) { item in
                Button {
                    quickEditQuantityG = nil
                    selectedItem = item
                } label: {
                    FoodResultRow(item: item)
                }
                .listRowBackground(Color.bgCard)
            }

            if !trimmedQuery.isEmpty {
                Button {
                    isFreeText = true
                } label: {
                    Label(
                        String(localized: "food.freetext.cta \(trimmedQuery)"),
                        systemImage: "square.and.pencil"
                    )
                    .font(.bodyMedium)
                    .foregroundStyle(Color.accent)
                }
                .listRowBackground(Color.bgCard)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if viewModel.searchResults.isEmpty && trimmedQuery.isEmpty && viewModel.topFoods.isEmpty {
                ContentUnavailableView(
                    String(localized: "food.search.empty.title"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "food.search.empty.message"))
                )
            }
        }
    }

    // MARK: - Helpers

    private var trimmedQuery: String {
        viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleScan(_ result: BarcodeScanResult) {
        switch result {
        case .cancelled:
            return
        case .failure:
            scanMessage = String(localized: "food.scan.error.message")
        case .code(let barcode):
            Task { @MainActor in
                do {
                    if let item = try await viewModel.lookup(barcode: barcode) {
                        selectedItem = item
                    } else {
                        scanMessage = String(localized: "food.scan.not_found.message \(barcode)")
                    }
                } catch {
                    scanMessage = String(localized: "food.scan.error.message")
                }
            }
        }
    }
}

// MARK: - Result row (mirrors the diary picker)

private struct FoodResultRow: View {
    let item: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                FoodSourceBadge(source: item.source)
                Spacer()
            }
            HStack(spacing: 8) {
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(per100gSummary)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var per100gSummary: String {
        "\(NutritionFormat.energy(item.energyKcal100g)) / 100 \(String(localized: "food.unit.g"))"
    }
}
