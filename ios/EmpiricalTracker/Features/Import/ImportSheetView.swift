import Biomarkers
import Core
import SwiftUI
import UniformTypeIdentifiers

/// Full-screen sheet presented when the user taps the import button.
/// Covers three states:
///   1. Idle — "Pick file" button + optional drag-target hint.
///   2. Uploading — indeterminate/determinate progress ring.
///   3. Result — success summary or error with retry.
struct ImportSheetView: View {
    @Bindable var viewModel: ImportViewModel
    @State private var isDocumentPickerPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgBase.ignoresSafeArea()
                phaseView
            }
            .navigationTitle("Import Blood Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.dismiss() }
                        .foregroundStyle(Color.accent)
                        .disabled(viewModel.isUploading)
                }
            }
        }
        .sheet(isPresented: $isDocumentPickerPresented) {
            DocumentPickerView { url in
                Task { await viewModel.upload(fileURL: url) }
            }
        }
        // Auto-start when the app was launched from Files/AirDrop
        .task {
            if let pending = viewModel.pendingFileURL {
                await viewModel.upload(fileURL: pending)
            }
        }
    }

    // MARK: - Phase routing

    @ViewBuilder
    private var phaseView: some View {
        switch viewModel.phase {
        case .idle:
            idleView
        case .uploading(let progress):
            uploadingView(progress: progress)
        case .success(let result):
            successView(result: result)
        case .failure(let message):
            failureView(message: message)
        case .deleted:
            deletedView
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accent)

                VStack(spacing: 6) {
                    Text("Import a lab report")
                        .font(.headlineLarge)
                        .foregroundStyle(Color.textPrimary)
                    Text("Select the .xlsx file you received from your laboratory. Norwegian decimal commas and date formats are handled automatically.")
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }

            Button {
                isDocumentPickerPresented = true
            } label: {
                Label("Choose file…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 32)

            Text("You can also open a .xlsx directly from Mail, Files, or AirDrop — the app will import it automatically.")
                .font(.bodySmall)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Divider()
                .padding(.horizontal, 32)

            Button(role: .destructive) {
                viewModel.showDeleteAllConfirmation = true
            } label: {
                Label("Delete all records…", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isDeletingAll)
            .padding(.horizontal, 32)
            .confirmationDialog(
                "Delete all blood test records?",
                isPresented: $viewModel.showDeleteAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    Task { await viewModel.deleteAllRecords() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all imported panels and results. This cannot be undone.")
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Deleted

    private var deletedView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "trash.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.textMuted)

            VStack(spacing: 6) {
                Text("All records deleted")
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)
                Text("All blood test panels and results have been removed.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button("Import new file") {
                viewModel.reset()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 32)

            Button("Done") {
                viewModel.dismiss()
            }
            .font(.headlineSmall)
            .foregroundStyle(Color.accent)

            Spacer()
        }
        .padding()
    }

    // MARK: - Uploading

    private func uploadingView(progress: Double) -> some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.borderSubtle, lineWidth: 6)
                    .frame(width: 88, height: 88)

                if progress > 0 {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.accent)
                        .scaleEffect(1.6)
                }

                if progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(.numericSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            VStack(spacing: 6) {
                Text("Uploading…")
                    .font(.headlineMedium)
                    .foregroundStyle(Color.textPrimary)
                Text("The server is parsing your lab report. This usually takes a few seconds.")
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Success

    private func successView(result: ImportResult) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.inRange)

            VStack(spacing: 6) {
                Text("Import complete")
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)
                Text("Your blood test has been added.")
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
            }

            // Summary stats card
            CardView {
                VStack(spacing: 0) {
                    summaryRow(label: "Results imported", value: "\(result.resultsInserted)", color: .textPrimary)
                    Divider().padding(.vertical, 10)
                    summaryRow(label: "Panels created", value: "\(result.panelsCreated)", color: .textPrimary)
                    if result.skippedRows > 0 {
                        Divider().padding(.vertical, 10)
                        summaryRow(label: "Skipped rows", value: "\(result.skippedRows)", color: .textMuted)
                    }
                }
            }
            .padding(.horizontal, 24)

            // Per-row errors (if any)
            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Warnings")
                        .font(.headlineSmall)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(result.errors, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.bodySmall)
                            .foregroundStyle(Color.outRange)
                    }
                }
                .padding(.horizontal, 24)
            }

            Button("Done") { viewModel.dismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }

    private func summaryRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.numericSmall)
                .foregroundStyle(color)
        }
    }

    // MARK: - Failure

    private func failureView(message: String) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.outRange)

            VStack(spacing: 6) {
                Text("Import failed")
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 16) {
                Button("Try again") {
                    viewModel.reset()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Cancel") {
                    viewModel.dismiss()
                }
                .font(.headlineSmall)
                .foregroundStyle(Color.accent)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - UIDocumentPicker bridge

/// Wraps `UIDocumentPickerViewController` so SwiftUI can present it.
/// Restricts selection to `.xlsx` files (content type `spreadsheet`).
private struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType(filenameExtension: "xlsx") ?? .spreadsheet,
            .spreadsheet,
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - Preview

#Preview("Idle") {
    let env = AppEnvironment.preview()
    let vm = ImportViewModel(
        biomarkersRepo: env.biomarkers,
        importService: env.biomarkersImport
    )
    return ImportSheetView(viewModel: vm)
        .environment(env)
}

#Preview("Uploading") {
    let env = AppEnvironment.preview()
    let vm = ImportViewModel(
        biomarkersRepo: env.biomarkers,
        importService: env.biomarkersImport
    )
    vm.phase = .uploading(progress: 0.62)
    return ImportSheetView(viewModel: vm)
        .environment(env)
}

#Preview("Success") {
    let env = AppEnvironment.preview()
    let vm = ImportViewModel(
        biomarkersRepo: env.biomarkers,
        importService: env.biomarkersImport
    )
    vm.phase = .success(ImportResult(
        panelId: "p-1",
        panelsCreated: 1,
        resultsInserted: 18,
        skippedRows: 2,
        errors: ["Row 14: unrecognised marker 'Mg-fix'"]
    ))
    return ImportSheetView(viewModel: vm)
        .environment(env)
}

#Preview("Failure") {
    let env = AppEnvironment.preview()
    let vm = ImportViewModel(
        biomarkersRepo: env.biomarkers,
        importService: env.biomarkersImport
    )
    vm.phase = .failure("Wrong file format. Please upload a valid Norwegian lab .xlsx file.")
    return ImportSheetView(viewModel: vm)
        .environment(env)
}

#Preview("Deleted") {
    let env = AppEnvironment.preview()
    let vm = ImportViewModel(
        biomarkersRepo: env.biomarkers,
        importService: env.biomarkersImport
    )
    vm.phase = .deleted
    return ImportSheetView(viewModel: vm)
        .environment(env)
}
