import Biomarkers
import Core
import Foundation
import Observation

/// Drives the import sheet UI.
/// The view owns no mutable state — all observable state lives here so the
/// sheet can be dismissed and re-presented without losing progress feedback.
@MainActor
@Observable
final class ImportViewModel {

    // MARK: - State

    enum Phase: Equatable {
        /// Waiting for the user to pick a file.
        case idle
        /// Upload is in progress (0 → 1).
        case uploading(progress: Double)
        /// Server finished; showing result summary.
        case success(ImportResult)
        /// Something went wrong.
        case failure(String)
        /// All records were deleted.
        case deleted
    }

    var phase: Phase = .idle
    var isDeletingAll = false
    var showDeleteAllConfirmation = false

    /// Set to true by the dashboard toolbar button or an incoming share-sheet URL.
    var isPresented = false

    /// When the app receives an .xlsx via Files/AirDrop, this URL is queued here
    /// so the sheet auto-starts the upload on presentation.
    var pendingFileURL: URL?

    // MARK: - Dependencies

    private let biomarkersRepo: BiomarkersRepository
    private let importService: BiomarkersImportService

    init(biomarkersRepo: BiomarkersRepository, importService: BiomarkersImportService) {
        self.biomarkersRepo = biomarkersRepo
        self.importService = importService
    }

    // MARK: - Actions

    /// Called when the user selects a file from UIDocumentPicker or the sheet
    /// receives a pre-queued `pendingFileURL`.
    func upload(fileURL: URL) async {
        phase = .uploading(progress: 0)

        // Security-scoped resources from the document picker must be accessed explicitly.
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let result = try await biomarkersRepo.importXLSX(
                fileURL: fileURL,
                importService: importService,
                onProgress: { [weak self] fraction in
                    self?.phase = .uploading(progress: fraction)
                }
            )
            phase = .success(result)
        } catch let e as APIError {
            phase = .failure(Self.message(for: e))
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// Turns a raw API error into actionable guidance, distinguishing a server-side
    /// failure (5xx — nothing the user can fix) from a rejected file (4xx).
    private static func message(for error: APIError) -> String {
        switch error {
        case .serverError(409, _):
            return "A panel for this date already exists. Delete the existing records first, then re-import."
        case .serverError(let code, let detail) where code >= 500:
            let base = "The server couldn't process this file (error \(code)). "
                + "This is a problem on the server, not your file — please try again shortly."
            if let detail, !detail.isEmpty, detail != "Internal Server Error" {
                return base + "\n\n" + detail
            }
            return base
        case .serverError(_, let detail):
            return detail ?? "The file was rejected. Make sure it's an unmodified .xlsx lab report."
        case .unauthorized:
            return "Your session expired. Please sign in again and retry the import."
        default:
            return error.localizedDescription
        }
    }

    func deleteAllRecords() async {
        isDeletingAll = true
        do {
            try await biomarkersRepo.deleteAllPanels()
            phase = .deleted
        } catch let e as APIError {
            phase = .failure(Self.message(for: e))
        } catch {
            phase = .failure(error.localizedDescription)
        }
        isDeletingAll = false
    }

    func reset() {
        phase = .idle
        pendingFileURL = nil
    }

    func dismiss() {
        isPresented = false
        reset()
    }

    // MARK: - Computed helpers

    var uploadProgress: Double {
        if case .uploading(let p) = phase { return p }
        return 0
    }

    var isUploading: Bool {
        if case .uploading = phase { return true }
        return false
    }
}
