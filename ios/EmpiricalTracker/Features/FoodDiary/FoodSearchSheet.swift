import Core
import SwiftUI

/// The add-food sheet: pick a source, search (or scan a barcode), choose a result, or
/// fall back to a free-text entry. Tapping a result opens `LogFoodSheet` for quantity.
struct FoodSearchSheet: View {
    @Bindable var viewModel: FoodDiaryViewModel

    @State private var selectedItem: FoodItem?
    @State private var isFreeText = false
    @State private var isScanning = false
    @State private var scanMessage: String?

    /// Barcode that was scanned but not found — triggers the label-scan prompt.
    @State private var missedBarcode: String?
    /// True when the label-capture + review flow is open.
    @State private var isCapturingLabel = false
    /// True when AddCustomFoodView is open for manual entry (no OCR).
    @State private var isAddingCustom = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                filterBar
                resultsList
            }
            .background(Color.bgBase)
            .navigationTitle(String(localized: "food.search.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        viewModel.isAddPresented = false
                    }
                }
            }
            // Quantity entry for a searched / scanned product.
            .sheet(item: $selectedItem) { item in
                LogFoodSheet(viewModel: viewModel, item: item)
            }
            // Free-text entry (no product match).
            .sheet(isPresented: $isFreeText) {
                LogFoodSheet(viewModel: viewModel, freeTextName: trimmedQuery)
            }
            // Native barcode scanner.
            .fullScreenCover(isPresented: $isScanning) {
                BarcodeScannerView { result in
                    isScanning = false
                    handleScan(result)
                }
            }
            // Nutrition label OCR capture → review → save (all in one hierarchy).
            .fullScreenCover(isPresented: $isCapturingLabel) {
                NutritionLabelCaptureView(
                    prefilledBarcode: missedBarcode,
                    viewModel: viewModel,
                    onDone: { isCapturingLabel = false }
                )
            }
            // Manual custom food entry (+ button, no OCR).
            .sheet(isPresented: $isAddingCustom) {
                AddCustomFoodView(
                    viewModel: viewModel,
                    parsedLabel: nil,
                    prefilledBarcode: missedBarcode
                )
            }
            // Barcode not found — offer label scan or dismiss.
            .alert(
                String(localized: "food.scan.not_found.title"),
                isPresented: Binding(
                    get: { scanMessage != nil },
                    set: { if !$0 { scanMessage = nil } }
                )
            ) {
                Button(String(localized: "food.scan.add_product")) {
                    scanMessage = nil
                    isCapturingLabel = true
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    scanMessage = nil
                    missedBarcode = nil
                }
            } message: {
                Text(scanMessage ?? "")
            }
        }
    }

    // MARK: - Filter bar (source chip + optional scan)

    /// Secondary controls beneath the search field: the source filter chip on the
    /// left, and — only for sources that carry barcodes — a compact scan button
    /// plus an "add product" button for manual / OCR entry.
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
            // Dedicated camera button to scan a nutrition label directly.
            Button {
                missedBarcode = nil
                isCapturingLabel = true
            } label: {
                Image(systemName: "camera")
                    .font(.bodyMedium)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Color.accent)
            .accessibilityLabel(String(localized: "food.label.capture.button"))
            // Always-visible "add my food" shortcut (manual, no OCR).
            Button {
                missedBarcode = nil
                isAddingCustom = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.bodyMedium)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Color.accent)
            .accessibilityLabel(String(localized: "food.custom.add_button_accessibility"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Search field

    private var searchField: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(viewModel.isSearching ? Color.accent : Color.textMuted)
                    .symbolEffect(.pulse, isActive: viewModel.isSearching)
                TextField(String(localized: "food.search.placeholder"), text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onChange(of: viewModel.searchQuery) { viewModel.scheduleSearch() }
                    .onSubmit { Task { await viewModel.searchNow() } }
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.accent)
                }
            }
            .padding(10)
            .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 10))

            if viewModel.isSearching {
                SearchingBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, viewModel.isSearching ? 4 : 8)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if viewModel.isSearching && viewModel.searchResults.isEmpty {
            SearchPlaceholderList()
                .transition(.opacity)
        } else {
            List {
                ForEach(viewModel.searchResults) { item in
                    Button {
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
                if viewModel.searchResults.isEmpty && trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        String(localized: "food.search.empty.title"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "food.search.empty.message"))
                    )
                }
            }
            .transition(.opacity)
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
                        // Barcode miss — save it so the label-capture flow can pre-fill it.
                        missedBarcode = barcode
                        scanMessage = String(localized: "food.scan.not_found.message \(barcode)")
                    }
                } catch {
                    scanMessage = String(localized: "food.scan.error.message")
                }
            }
        }
    }
}

// MARK: - Searching banner

/// A slim pill that slides in just below the search field while a query is in flight.
private struct SearchingBanner: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .tint(Color.accent)
            Text(String(localized: "food.search.searching"))
                .font(.labelMedium)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.bgElevated, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shimmer placeholder list

/// Skeleton rows shown while isSearching and no results have arrived yet.
private struct SearchPlaceholderList: View {
    var body: some View {
        List(0..<6, id: \.self) { _ in
            ShimmerRow()
                .listRowBackground(Color.bgCard)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
    }
}

private struct ShimmerRow: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerGradient)
                .frame(height: 14)
                .frame(maxWidth: .infinity)
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 80, height: 11)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 60, height: 11)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.textMuted.opacity(0.15), location: max(0, phase - 0.3)),
                .init(color: Color.textMuted.opacity(0.30), location: phase),
                .init(color: Color.textMuted.opacity(0.15), location: min(1, phase + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Result row

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

    /// Per-100 g energy preview, e.g. "271 kcal / 100 g".
    private var per100gSummary: String {
        "\(NutritionFormat.energy(item.energyKcal100g)) / 100 \(String(localized: "food.unit.g"))"
    }
}
