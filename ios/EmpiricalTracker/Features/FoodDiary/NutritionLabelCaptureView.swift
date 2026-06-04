import Core
import FoodDiary
import SwiftUI
import Vision

/// Full-screen sheet that lets the user photograph a nutrition label.
/// On capture it runs on-device OCR (Vision) then posts the text to the backend
/// for Claude Haiku to extract structured nutrients. After parsing succeeds,
/// AddCustomFoodView is presented inline so the entire flow stays in one
/// view hierarchy — no cross-hierarchy state handoff.
struct NutritionLabelCaptureView: View {
    /// Optional barcode that triggered this flow (barcode-miss path).
    let prefilledBarcode: String?
    let viewModel: FoodDiaryViewModel
    /// Called when the user cancels or completes the flow (use to dismiss the fullScreenCover).
    let onDone: () -> Void

    @State private var phase: Phase = .idle
    @State private var isCapturing = false
    @State private var errorMessage: String?
    /// Set when parsing succeeds — triggers AddCustomFoodView sheet.
    @State private var parsedLabel: ParsedLabel?

    init(
        prefilledBarcode: String? = nil,
        viewModel: FoodDiaryViewModel,
        onDone: @escaping () -> Void
    ) {
        self.prefilledBarcode = prefilledBarcode
        self.viewModel = viewModel
        self.onDone = onDone
    }

    enum Phase {
        case idle
        case recognising
        case parsing
        case done
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgBase.ignoresSafeArea()
                content
            }
            .navigationTitle(String(localized: "food.label.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { onDone() }
                }
            }
            .alert(
                String(localized: "food.label.error.title"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $isCapturing) {
            CameraPickerView { image in
                isCapturing = false
                if let image {
                    recognise(image: image)
                }
            }
        }
        // Present AddCustomFoodView here, inside the same fullScreenCover hierarchy.
        .sheet(item: $parsedLabel) { label in
            AddCustomFoodView(
                viewModel: viewModel,
                parsedLabel: label,
                prefilledBarcode: prefilledBarcode,
                onSaved: { onDone() }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            idleView
        case .recognising:
            progressView(message: String(localized: "food.label.ocr.progress"))
        case .parsing:
            progressView(message: String(localized: "food.label.parsing.progress"))
        case .done:
            progressView(message: String(localized: "food.label.parsing.progress"))
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(Color.accent)

            Text(String(localized: "food.label.idle.title"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(String(localized: "food.label.idle.message"))
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let barcode = prefilledBarcode {
                Text(String(localized: "food.label.barcode.hint \(barcode)"))
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                isCapturing = true
            } label: {
                Label(String(localized: "food.label.capture.button"), systemImage: "camera")
                    .font(.bodyMedium.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func progressView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.bodyMedium)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - OCR

    private func recognise(image: UIImage) {
        phase = .recognising
        guard let cgImage = image.cgImage else {
            errorMessage = String(localized: "food.label.error.message")
            phase = .idle
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                Task { @MainActor in
                    errorMessage = error.localizedDescription
                    phase = .idle
                }
                return
            }
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")

            Task { @MainActor in
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = String(localized: "food.label.error.no_text")
                    phase = .idle
                    return
                }
                await parse(ocrText: text)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    // MARK: - Backend parse

    @MainActor
    private func parse(ocrText: String) async {
        phase = .parsing
        do {
            let label = try await viewModel.repo.parseLabel(ocrText: ocrText)
            print("🔍 OCR-DEBUG ParsedLabel: name=\(label.foodName ?? "nil") energy=\(label.energyKcal100g.map(String.init) ?? "nil") carbs=\(label.carbs100g.map(String.init) ?? "nil") protein=\(label.protein100g.map(String.init) ?? "nil") fat=\(label.fat100g.map(String.init) ?? "nil") sodium=\(label.sodiumMg100g.map(String.init) ?? "nil")")
            parsedLabel = label   // triggers .sheet(item:) — safe, same hierarchy
            phase = .done
        } catch {
            print("🔍 OCR-DEBUG parse error: \(error)")
            errorMessage = String(localized: "food.label.error.message")
            phase = .idle
        }
    }
}

// MARK: - Camera picker (UIImagePickerController bridge)

private struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
