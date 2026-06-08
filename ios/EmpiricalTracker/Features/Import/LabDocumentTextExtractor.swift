import CoreGraphics
import Foundation
import PDFKit
import UIKit
import Vision

/// On-device text extraction for lab documents (ADR-032 Phase 1).
///
/// Privacy posture A (the default): the document never leaves the phone — we
/// pull text from it here and only that text is sent to the backend. Two paths:
///   • **Text-based PDF** (portal exports): read the embedded text layer with
///     PDFKit. Near-perfect, free, no OCR error. *Tried first.*
///   • **Scanned PDF / photo**: rasterize / load the image and run Vision OCR.
///
/// The consent-gated "send the image to a vision model" posture (Option B) is a
/// later phase and is intentionally not implemented here.
enum LabDocumentTextExtractor {

    enum ExtractionError: LocalizedError {
        case unreadable
        case noText

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file couldn't be read. Try a PDF or a clear photo of the report."
            case .noText:
                return "No readable text was found in that document."
            }
        }
    }

    struct Extraction {
        let text: String
        /// Maps onto `lab_imports.source_kind`: "pdf" or "image".
        let sourceKind: String
    }

    /// Extract text from a picked file URL (PDF or image). The caller is
    /// responsible for security-scoped access around this call.
    static func extract(from url: URL) async throws -> Extraction {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try await extractPDF(url: url)
        }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            throw ExtractionError.unreadable
        }
        let text = try await ocr(image: image)
        guard !text.isEmpty else { throw ExtractionError.noText }
        return Extraction(text: text, sourceKind: "image")
    }

    // MARK: - PDF

    private static func extractPDF(url: URL) async throws -> Extraction {
        guard let doc = PDFDocument(url: url) else { throw ExtractionError.unreadable }

        // 1. Prefer the embedded text layer — highest fidelity, no OCR.
        if let layer = doc.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           layer.count >= 20 {
            return Extraction(text: layer, sourceKind: "pdf")
        }

        // 2. No usable text layer → rasterize each page and OCR it.
        var pages: [String] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2  // upsample for OCR accuracy
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.set()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }
            if let pageText = try? await ocr(image: image), !pageText.isEmpty {
                pages.append(pageText)
            }
        }

        let text = pages.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtractionError.noText
        }
        return Extraction(text: text, sourceKind: "pdf")
    }

    // MARK: - Vision OCR

    private static func ocr(image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw ExtractionError.unreadable }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Norwegian-first reports, with English fallback.
            request.recognitionLanguages = ["nb", "en"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
