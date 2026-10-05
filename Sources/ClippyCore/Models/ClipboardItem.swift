import Foundation

public enum ClipKind: String, Codable, Sendable {
    case text, url, image, file
}

public enum ClipCategory: String, Codable, Sendable, CaseIterable {
    case link, code, command, email, phone, json, path, message, image, file, other
}

public struct ClipboardItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ClipKind
    public var category: ClipCategory
    public var contentHash: String
    public var text: String?
    public var preview: String
    public var blobPath: String?
    public var thumbPath: String?
    public var byteSize: Int
    public var sourceBundle: String?
    public var sourceName: String?
    public var createdAt: Date
    public var lastUsedAt: Date
    public var copyCount: Int
    public var pinned: Bool
    public var pinOrder: Int?
    public var expiresAt: Date?

    public init(id: String = UUID().uuidString, kind: ClipKind, category: ClipCategory,
                contentHash: String, text: String? = nil, preview: String,
                blobPath: String? = nil, thumbPath: String? = nil, byteSize: Int,
                sourceBundle: String? = nil, sourceName: String? = nil,
                createdAt: Date = Date(), lastUsedAt: Date? = nil, copyCount: Int = 1,
                pinned: Bool = false, pinOrder: Int? = nil, expiresAt: Date? = nil) {
        self.id = id; self.kind = kind; self.category = category
        self.contentHash = contentHash; self.text = text; self.preview = preview
        self.blobPath = blobPath; self.thumbPath = thumbPath; self.byteSize = byteSize
        self.sourceBundle = sourceBundle; self.sourceName = sourceName
        self.createdAt = createdAt; self.lastUsedAt = lastUsedAt ?? createdAt
        self.copyCount = copyCount; self.pinned = pinned; self.pinOrder = pinOrder
        self.expiresAt = expiresAt
    }
}

/// How long unpinned items live. Default 24h.
public enum RetentionPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case hour1, hour6, hour12, hour24, day3, day7, never
    public var id: String { rawValue }
    public static let `default` = RetentionPolicy.hour24

    public var interval: TimeInterval? {
        switch self {
        case .hour1: return 3600
        case .hour6: return 6 * 3600
        case .hour12: return 12 * 3600
        case .hour24: return 24 * 3600
        case .day3: return 3 * 86400
        case .day7: return 7 * 86400
        case .never: return nil
        }
    }
    public var label: String {
        switch self {
        case .hour1: return "1 hour"
        case .hour6: return "6 hours"
        case .hour12: return "12 hours"
        case .hour24: return "24 hours"
        case .day3: return "3 days"
        case .day7: return "7 days"
        case .never: return "Never"
        }
    }
    public func expiry(from date: Date) -> Date? { interval.map { date.addingTimeInterval($0) } }
}
