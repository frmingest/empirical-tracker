import Core
import Recipes
import SwiftUI

/// Sheet that lets the user paste a recipe URL; the backend fetches the page and
/// extracts a recipe (via schema.org/JSON-LD or a Claude fallback) and returns a
/// preview. On success, `RecipesView` presents `RecipeFormView` prefilled with the
/// result so the user can review and edit before saving.
struct RecipeImportView: View {
    let viewModel: RecipesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var isImporting = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "recipes.import.url.placeholder"), text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                } footer: {
                    Text(String(localized: "recipes.import.url.footer"))
                }
            }
            .navigationTitle(String(localized: "recipes.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(String(localized: "recipes.import.action")) {
                            Task { await importRecipe() }
                        }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { isFocused = true }
    }

    private var trimmedUrl: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedUrl.isEmpty }

    @MainActor
    private func importRecipe() async {
        guard isValid else { return }
        isImporting = true
        defer { isImporting = false }
        if await viewModel.importRecipe(from: trimmedUrl) {
            dismiss()
        }
    }
}
