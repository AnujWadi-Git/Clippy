import Foundation

/// Backup / transfer of clipboard history as JSON. The file is PLAINTEXT, so the UI warns before writing it.
/// Images are not included (they live as files); held-sensitive items never are.
public enum HistoryArchive {
    public struct Entry: Codable, Equatable {
        public var text: String
        public var kind: String          // "text" | "url" | "file"
        public var pinned: Bool
        public var copyCount: Int
        public var createdAt: Date
        public var source: String?
    }
    public struct Archive: Codable {
        public var format = "clippy-history"
        public var version = 1
        public var exportedAt = Date()
        public var entries: [Entry]
    }
    public struct ImportResult: Equatable {
        public var imported = 0, duplicates = 0, skipped = 0, pinned = 0
        public init(imported: Int = 0, duplicates: Int = 0, skipped: Int = 0, pinned: Int = 0) {
            self.imported = imported; self.duplicates = duplicates; self.skipped = skipped; self.pinned = pinned
        }
    }
    public enum ArchiveError: Error, LocalizedError {
        case notAnArchive
        public var errorDescription: String? { "That file isn’t a Clippy history export." }
    }

    public static func export(_ items: [ClipboardItem], pinnedOnly: Bool) throws -> Data {
        let entries = items.compactMap { i -> Entry? in
            guard !i.isHeldSensitive, let text = i.text, [.text, .url, .file].contains(i.kind), !pinnedOnly || i.pinned else { return nil }
            return Entry(text: text, kind: i.kind.rawValue, pinned: i.pinned, copyCount: i.copyCount, createdAt: i.createdAt, source: i.sourceName)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(Archive(entries: entries))
    }

    /// Imports through the normal capture pipeline, so sensitive content is still dropped. Imported unpinned items
    /// start a fresh retention window (importing is a deliberate user action).
    public static func importArchive(_ data: Data, pipeline: CapturePipeline, repository: ClipboardRepository) throws -> ImportResult {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        guard let archive = try? dec.decode(Archive.self, from: data), archive.format == "clippy-history" else { throw ArchiveError.notAnArchive }
        var result = ImportResult()
        // Oldest first so the most recent entry ends up on top.
        for e in archive.entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            let payload: CapturedClip.Payload = e.kind == "file" ? .files(e.text.split(separator: "\n").map(String.init)) : .text(e.text)
            let outcome = pipeline.process(CapturedClip(payload: payload, sourceName: e.source ?? "Imported"))
            var id: String?
            switch outcome {
            case .stored(let i): id = i; result.imported += 1
            case .duplicate(let i): id = i; result.duplicates += 1
            default: result.skipped += 1
            }
            if e.pinned, let id { try? repository.setPinned(id: id, true); result.pinned += 1 }
        }
        return result
    }
}
