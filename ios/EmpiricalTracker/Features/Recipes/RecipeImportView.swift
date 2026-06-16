import Core
import Recipes
import SwiftUI
import UniformTypeIdentifiers

/// Sheet that lets the user pick a PDF saved from a recipe page (via the browser's
/// Print → Save as PDF action). The PDF is uploaded to the backend, which extracts
/// the recipe text with pypdf and parses it with Claude. On success, `RecipesView`
/// presents `RecipeFormView` prefilled with the result so the user can review and
/// edit before saving.
struct RecipeImportView: View {
    let viewModel: RecipesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isPickerPresented = false
    @State private var isImporting = false
    @State private var pickedFileName: String?

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
                            Text(
                                pickedFileName ?? String(localized: "recipes.import.pdf.pick")
                            )
                            .foregroundStyle(pickedFileName != nil ? Color.textPrimary : Color.textSecondary)
                            Spacer()
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
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    }
                }
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
        case .failure:
            return
        case .success(let url):
            pickedFileName = url.lastPathComponent
            isImporting = true
            defer { isImporting = false }
            guard url.startAccessingSecurityScopedResource() else {
                viewModel.errorMessage = String(localized: "recipes.import.pdf.access_error")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                if await viewModel.importRecipe(fromPDF: data, fileName: url.lastPathComponent) {
                    dismiss()
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}
