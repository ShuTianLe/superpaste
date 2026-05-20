import AppKit
import Foundation
import Vision

public enum LocalIntelligence {
    public static func makePNGThumbnail(from data: Data, maxDimension: CGFloat = 320) -> Data? {
        guard let image = NSImage(data: data) else {
            return nil
        }
        let original = image.size
        guard original.width > 0, original.height > 0 else {
            return nil
        }

        let scale = min(maxDimension / original.width, maxDimension / original.height, 1)
        let targetSize = NSSize(width: original.width * scale, height: original.height * scale)
        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()

        guard let tiff = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    public static func recognizeText(inImageData data: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        do {
            try VNImageRequestHandler(data: data, options: [:]).perform([request])
            let text = request.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        } catch {
            return nil
        }
    }

    public static func matches(_ item: ClipboardItem, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return true
        }

        let haystacks = [
            item.previewText,
            item.sourceName ?? "",
            item.sourceBundleId ?? "",
            item.primaryType,
            item.blobRefs.compactMap(\.ocrText).joined(separator: "\n")
        ]
        return haystacks.contains { $0.lowercased().contains(normalized) }
    }
}

public extension ClipboardPayload {
    var isImagePayload: Bool {
        let lowered = uti.lowercased()
        return lowered.contains("public.png")
            || lowered.contains("public.tiff")
            || lowered.contains("image")
    }
}
