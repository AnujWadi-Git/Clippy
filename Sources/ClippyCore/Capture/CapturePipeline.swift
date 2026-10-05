import Foundation

/// What the monitor read off the pasteboard (plain data, so the pipeline is testable without AppKit).
public struct CapturedClip: Sendable {
    public enum Payload: Sendable { case text(String), image(Data), files([String]) }
    public var payload: Payload
    public var pasteboardTypes: [String]
    public var sourceBundle: String?
    public var sourceName: String?
    /// Original formatting (pasteboard type → bytes), e.g. public.rtf / public.html. Only for text payloads.
    public var rich: [String: Data]
    public init(payload: Payload, pasteboardTypes: [String] = [], sourceBundle: String? = nil, sourceName: String? = nil, rich: [String: Data] = [:]) {
        self.payload = payload; self.pasteboardTypes = pasteboardTypes; self.rich = rich
        self.sourceBundle = sourceBundle; self.sourceName = sourceName
    }
}

public enum CaptureOutcome: Equatable, Sendable {
    case stored(String), duplicate(String)
    case ignoredApp, droppedSensitive(SensitiveReason), heldInMemory(SensitiveReason)
    case tooLarge, empty, failed
}

/// filter → sensitive check → hash/dedupe → classify → persist.
/// Sensitive detection happens strictly BEFORE anything is written or indexed.
public final class CapturePipeline: @unchecked Sendable {
    public static let maxTextBytes = 5_000_000
    public static let maxImageBytes = 10_000_000

    private let repo: ClipboardRepository
    private let settings: SettingsManager

    public init(repository: ClipboardRepository, settings: SettingsManager) {
        self.repo = repository; self.settings = settings
    }

    @discardableResult
    public func process(_ clip: CapturedClip) -> CaptureOutcome {
        let detector = SensitiveContentDetector(ignoredBundles: settings.effectiveIgnoredBundles,
                                                dropBareNumericCodes: true)
        // User-excluded apps always apply (independent of the sensitive toggle).
        if let b = clip.sourceBundle?.lowercased(), settings.ignoredApps.contains(where: { $0.lowercased() == b }) { return .ignoredApp }

        var meta: SensitiveVerdict?
        if settings.protectSensitive { meta = detector.checkMetadata(pasteboardTypes: clip.pasteboardTypes, sourceBundle: clip.sourceBundle) }
        else if settings.ignorePasswordManagers, let b = clip.sourceBundle?.lowercased(), settings.effectiveIgnoredBundles.contains(where: { $0.lowercased() == b }) { return .ignoredApp }
        // Concealed/transient types and password-manager sources: never keep, not even in memory.
        if let m = meta { return .droppedSensitive(m.reason) }

        switch clip.payload {
        case .text(let raw):
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
            guard raw.utf8.count <= Self.maxTextBytes else { return .tooLarge }
            let category = ContentClassifier.classify(text: raw)
            let draft = ClipboardItem(kind: category == .link ? .url : .text, category: category,
                                      contentHash: DuplicateDetector.hash(text: raw), text: raw,
                                      preview: ContentClassifier.preview(raw), byteSize: raw.utf8.count,
                                      sourceBundle: clip.sourceBundle, sourceName: clip.sourceName)
            if settings.protectSensitive, let v = detector.check(text: raw) {
                if settings.sensitiveMode == .memoryOnly {
                    var d = draft; d.preview = "🔒 " + String(repeating: "•", count: min(12, max(6, raw.count)))
                    d.category = .other
                    repo.addEphemeral(d)
                    return .heldInMemory(v.reason)
                }
                return .droppedSensitive(v.reason)
            }
            return store(attachRich(clip.rich, to: draft))

        case .files(let paths):
            guard !paths.isEmpty else { return .empty }
            let joined = paths.joined(separator: "\n")
            let names = paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            let draft = ClipboardItem(kind: .file, category: .file, contentHash: DuplicateDetector.hash(text: "files:" + joined),
                                      text: joined, preview: ContentClassifier.preview(names), byteSize: joined.utf8.count,
                                      sourceBundle: clip.sourceBundle, sourceName: clip.sourceName)
            return store(draft)

        case .image(let data):
            guard !data.isEmpty else { return .empty }
            guard data.count <= Self.maxImageBytes else { return .tooLarge }
            let hash = DuplicateDetector.hash(data: data, kind: .image)
            if settings.ignoreDuplicates, repo.exists(hash: hash) {
                // No need to write files for a known image.
                var d = ClipboardItem(kind: .image, category: .image, contentHash: hash, preview: "Image", byteSize: data.count)
                d.sourceBundle = clip.sourceBundle
                return store(d)
            }
            // OCR first: screenshots of secrets must be caught by the same detector as copied text.
            var ocr: String?
            if settings.ocrImages { ocr = ImageOCR.recognize(data) }
            if settings.protectSensitive, let t = ocr, let v = detector.check(text: t) {
                if settings.sensitiveMode == .memoryOnly {
                    repo.addEphemeral(ClipboardItem(kind: .text, category: .other, contentHash: hash, text: nil,
                                                    preview: "🔒 sensitive image", byteSize: data.count))
                    return .heldInMemory(v.reason)
                }
                return .droppedSensitive(v.reason)
            }
            do {
                let name = try repo.blobs.write(data)
                var thumb: String?
                if let t = repo.blobs.makeThumbnail(from: data) { thumb = try? repo.blobs.write(t) }
                let snippet = ocr.map { ContentClassifier.preview($0, limit: 90) }
                let draft = ClipboardItem(kind: .image, category: .image, contentHash: hash, text: ocr,
                                          preview: snippet.map { "Image · " + $0 } ?? "Image",
                                          blobPath: name, thumbPath: thumb, byteSize: data.count,
                                          sourceBundle: clip.sourceBundle, sourceName: clip.sourceName)
                return store(draft)
            } catch { return .failed }
        }
    }

    /// Stores formatting encrypted on disk. Skipped when no key is available (plain text still works).
    private func attachRich(_ rich: [String: Data], to draft: ClipboardItem) -> ClipboardItem {
        guard settings.keepFormatting, !rich.isEmpty, repo.blobs.canSeal, let blob = RichContent.encode(rich),
              let name = try? repo.blobs.writeSealed(blob) else { return draft }
        var d = draft
        d.richPath = name
        d.byteSize += blob.count
        return d
    }

    private func store(_ draft: ClipboardItem) -> CaptureOutcome {
        do {
            switch try repo.ingest(draft) {
            case .stored(let i): return .stored(i.id)
            case .duplicate(let i): return .duplicate(i.id)
            }
        } catch { return .failed }
    }
}
