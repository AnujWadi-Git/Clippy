import Foundation
import Vision
import ImageIO

/// On-device text recognition for copied images (Vision). Nothing leaves the Mac.
public enum ImageOCR {
    /// Recognised text joined by newlines, or nil if none / failure. Runs synchronously; call off the main thread.
    public static func recognize(_ data: Data, maxChars: Int = 4000) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maxChars))
    }
}
