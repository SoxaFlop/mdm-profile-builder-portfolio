import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

/// A local, temporary attachment used to give the assistant evidence from a
/// technician-provided document or screenshot. The original file is never
/// uploaded or copied into the profile.
struct AssistantAttachment: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case pdf = "PDF"
        case image = "Image"
    }

    let id: UUID
    let filename: String
    let kind: Kind
    let extractedText: String
    let pageOrImageCount: Int

    init(
        id: UUID = UUID(),
        filename: String,
        kind: Kind,
        extractedText: String,
        pageOrImageCount: Int
    ) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.extractedText = extractedText
        self.pageOrImageCount = pageOrImageCount
    }

    var promptExcerpt: String {
        let limit = 12_000
        let text = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = text.count > limit ? String(text.prefix(limit)) + "\n[Attachment excerpt truncated]" : text
        return "ATTACHMENT: \(filename) (\(kind.rawValue), \(pageOrImageCount) \(pageOrImageCount == 1 ? "page/image" : "pages/images"))\n\(excerpt.isEmpty ? "No readable text was found." : excerpt)"
    }
}

enum AssistantAttachmentProcessor {
    private static let maximumPDFPages = 120
    private static let maximumExtractedCharacters = 60_000

    static func analyse(url: URL) throws -> AssistantAttachment {
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if accessedSecurityScope { url.stopAccessingSecurityScopedResource() }
        }

        let contentType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
        if contentType?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return try analysePDF(url: url)
        }
        if contentType?.conforms(to: .image) == true {
            return try analyseImage(url: url)
        }
        throw AssistantAttachmentError.unsupportedFile
    }

    private static func analysePDF(url: URL) throws -> AssistantAttachment {
        guard let document = PDFDocument(url: url) else { throw AssistantAttachmentError.unreadablePDF }
        let count = document.pageCount
        guard count > 0 else { throw AssistantAttachmentError.unreadablePDF }

        let text = (0..<min(count, maximumPDFPages)).compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
        let summary = text.isEmpty
            ? "No selectable text was found in this PDF. It may be a scanned document; attach clear screenshots of the relevant pages so local OCR can read the visible text."
            : limitedText(text)
        return AssistantAttachment(
            filename: url.lastPathComponent,
            kind: .pdf,
            extractedText: summary,
            pageOrImageCount: count
        )
    }

    private static func analyseImage(url: URL) throws -> AssistantAttachment {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AssistantAttachmentError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let summary = text.isEmpty
            ? "No readable text was detected in this image. The local model can use OCR from screenshots and PDFs; it cannot yet interpret a visual layout or photograph without text."
            : limitedText(text)
        return AssistantAttachment(
            filename: url.lastPathComponent,
            kind: .image,
            extractedText: summary,
            pageOrImageCount: 1
        )
    }

    private static func limitedText(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.count > maximumExtractedCharacters
            ? String(cleaned.prefix(maximumExtractedCharacters)) + "\n[Attachment text truncated]"
            : cleaned
    }
}

enum AssistantAttachmentError: LocalizedError {
    case unsupportedFile
    case unreadablePDF
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a PDF or an image file."
        case .unreadablePDF: "This PDF could not be read locally."
        case .unreadableImage: "This image could not be read locally."
        }
    }
}
