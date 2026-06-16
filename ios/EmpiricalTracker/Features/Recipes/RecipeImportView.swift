import Core
import Recipes
import SwiftUI
import UniformTypeIdentifiers

/// Sheet that lets the user pick a PDF saved from a recipe page (via the browser's
/// Print → Save as PDF action). After a successful upload the user is pushed
/// directly to `RecipeFormView` within the same sheet so they can review and edit
/// before saving — avoiding the unreliable two-sheet-in-sequence pattern.
struct RecipeImportView: View {
    let viewModel: RecipesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var parsedRecipe: RecipePayload?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isPickerPresented = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundStyle(Color.accent)
                            Text(String(localized: "recipes.import.pdf.pick"))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            if isImporting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isImporting)
                } footer: {
                    Text(String(localized: "recipes.import.pdf.footer"))
                }
            }
            .navigationTitle(String(localized: "recipes.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .disabled(isImporting)
                }
            }
            .navigationDestination(item: $parsedRecipe) { recipe in
                // Push the review form inside the same sheet so we don't need a
                // second sheet — SwiftUI drops sequentially-presented sheets
                // when the first dismisses during its animation.
                RecipeFormView(viewModel: viewModel, prefill: recipe, onSave: { dismiss() })
            }
            .alert(
                String(localized: "recipes.error.title"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .fileImporter(
                isPresented: $isPickerPresented,
                allowedContentTypes: [UTType.pdf]
            ) { result in
                Task { await handlePicked(result) }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func handlePicked(_ result: Result<URL, any Error>) async {
        switch result {
        case .failure(let error):
            // Suppress user-cancelled (picker dismissed without picking) — not an error.
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
            errorMessage = error.localizedDescription
        case .success(let url):
            isImporting = true
            defer { isImporting = false }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = String(localized: "recipes.import.pdf.access_error")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                let payload = try await viewModel.repo.importFromPDF(data, fileName: url.lastPathComponent)
                parsedRecipe = payload
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
