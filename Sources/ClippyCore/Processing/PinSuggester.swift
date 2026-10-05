import Foundation

/// Notices things you copy over and over. It only SUGGESTS; pinning always needs the user's click.
public enum PinSuggester {
    public static let minimumCopies = 5
    static let eligible: Set<ClipCategory> = [.email, .phone, .command, .link, .code, .address, .message, .path, .json]

    public static func suggestion(from items: [ClipboardItem], dismissedHashes: Set<String>) -> ClipboardItem? {
        items.filter { i in
            !i.pinned && !i.isHeldSensitive && i.kind != .image && i.copyCount >= minimumCopies
                && eligible.contains(i.category) && !dismissedHashes.contains(i.contentHash)
                && (i.category != .message || (i.text?.count ?? 0) <= 300)
        }.max { $0.copyCount != $1.copyCount ? $0.copyCount < $1.copyCount : $0.lastUsedAt < $1.lastUsedAt }
    }
}
