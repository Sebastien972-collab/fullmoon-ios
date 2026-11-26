#if os(iOS)
import CoreTransferable
import Foundation
import SwiftUI
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

func composerCopy(_ key: String.LocalizationValue) -> String {
    String(localized: key, table: "Composer")
}

enum ComposerAttachmentError: LocalizedError {
    case tooLarge, unsupported, empty, locked, truncated, maximum

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? CocoaError)?.code == .userCancelled
    }

    var errorDescription: String? {
        switch self {
        case .tooLarge: composerCopy("Choose a file under 20 MB.")
        case .unsupported: composerCopy("Choose an image, PDF or UTF-8 text file.")
        case .empty: composerCopy("No readable text was found. Try a clearer photo or a PDF with selectable text.")
        case .locked: composerCopy("Unlock this PDF before attaching it.")
        case .truncated:
            composerCopy("This document is too long. Choose an excerpt of up to 6,000 characters and 30 PDF pages.")
        case .maximum: composerCopy("A message can include up to three attachments.")
        }
    }
}

enum ComposerExtraction {
    static let allowedTypes: [UTType] = [.image, .pdf, .text, .sourceCode, .json]
    private static let byteLimit = 20_000_000
    private static let characterLimit = 6_000

    static func file(_ url: URL) throws -> ComposerAttachmentContent {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ComposerAttachmentError.unsupported }
        guard let size = values.fileSize, size <= byteLimit else { throw ComposerAttachmentError.tooLarge }
        let suppliedType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        let type = suppliedType ?? UTType(filenameExtension: url.pathExtension)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= byteLimit else { throw ComposerAttachmentError.tooLarge }
        let text: String
        if type == .pdf || data.starts(with: "%PDF-".utf8) {
            text = try pdfText(data)
        } else if type?.conforms(to: .image) == true || isImage(data) {
            text = try imageText(data)
        } else {
            // Providers may omit a UTI for Markdown or source files. Only accept readable UTF-8.
            guard !data.contains(0), let decoded = String(data: data, encoding: .utf8) else {
                throw ComposerAttachmentError.unsupported
            }
            text = decoded
        }
        return try attachment(name: url.lastPathComponent, text: text)
    }

    static func photo(_ data: Data) throws -> ComposerAttachmentContent {
        guard data.count <= byteLimit else { throw ComposerAttachmentError.tooLarge }
        return try attachment(name: composerCopy("Photo"), text: imageText(data))
    }

    private static func attachment(name: String, text: String) throws -> ComposerAttachmentContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ComposerAttachmentError.empty }
        guard trimmed.count <= characterLimit else { throw ComposerAttachmentError.truncated }
        return ComposerAttachmentContent(name: name, text: trimmed)
    }

    private static func pdfText(_ data: Data) throws -> String {
        guard let pdf = PDFDocument(data: data) else { throw ComposerAttachmentError.unsupported }
        guard !pdf.isLocked else { throw ComposerAttachmentError.locked }
        guard pdf.pageCount <= 30 else { throw ComposerAttachmentError.truncated }
        var text = ""
        for index in 0..<pdf.pageCount {
            text += (pdf.page(at: index)?.string ?? "") + "\n"
            if text.count > characterLimit + 1 { throw ComposerAttachmentError.truncated }
        }
        return text
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    private static func imageText(_ data: Data) throws -> String {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw ComposerAttachmentError.unsupported }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n") ?? ""
    }
}

struct ComposerPhotoTransfer: Transferable {
    let content: ComposerAttachmentContent

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let content = try ComposerExtraction.file(received.file)
            return Self(content: ComposerAttachmentContent(name: composerCopy("Photo"), text: content.text))
        }
    }
}

struct ComposerAttachmentRow: View {
    let attachments: [ComposerAttachmentContent]
    let remove: (ComposerAttachmentContent) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { item in
                    Button { remove(item) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text(verbatim: item.name).lineLimit(1)
                            Image(systemName: "xmark.circle.fill")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(composerCopy("Remove attachment") + ", " + item.name)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
    }
}
#endif
