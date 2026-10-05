import Foundation

/// Persistence for ClipboardItem. All access is serialised on an internal lock.
public final class ClipboardDatabase: @unchecked Sendable {
    private let db: SQLiteDatabase
    private let lock = NSLock()

    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA secure_delete=ON")
        try db.execute("PRAGMA synchronous=NORMAL")
        try migrate()
    }

    private func migrate() throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS clip_item (
          id TEXT PRIMARY KEY, kind TEXT NOT NULL, category TEXT NOT NULL,
          content_hash TEXT NOT NULL UNIQUE, text TEXT, preview TEXT NOT NULL,
          blob_path TEXT, thumb_path TEXT, byte_size INTEGER NOT NULL,
          source_bundle TEXT, source_name TEXT,
          created_at REAL NOT NULL, last_used_at REAL NOT NULL,
          copy_count INTEGER NOT NULL DEFAULT 1, pinned INTEGER NOT NULL DEFAULT 0,
          pin_order INTEGER, expires_at REAL)
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_clip_last_used ON clip_item(last_used_at DESC)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_clip_expires ON clip_item(expires_at) WHERE pinned = 0")
    }

    private static let cols = "id,kind,category,content_hash,text,preview,blob_path,thumb_path,byte_size,source_bundle,source_name,created_at,last_used_at,copy_count,pinned,pin_order,expires_at"

    private static func item(_ r: SQLiteDatabase.Row) -> ClipboardItem {
        ClipboardItem(id: r.text(0)!, kind: ClipKind(rawValue: r.text(1) ?? "text") ?? .text,
                      category: ClipCategory(rawValue: r.text(2) ?? "other") ?? .other,
                      contentHash: r.text(3)!, text: r.text(4), preview: r.text(5) ?? "",
                      blobPath: r.text(6), thumbPath: r.text(7), byteSize: r.int(8),
                      sourceBundle: r.text(9), sourceName: r.text(10),
                      createdAt: r.date(11) ?? Date(), lastUsedAt: r.date(12),
                      copyCount: r.int(13), pinned: r.int(14) != 0,
                      pinOrder: r.optInt(15), expiresAt: r.date(16))
    }

    public func insert(_ i: ClipboardItem) throws {
        lock.lock(); defer { lock.unlock() }
        try db.execute("INSERT OR REPLACE INTO clip_item (\(Self.cols)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", [
            .text(i.id), .text(i.kind.rawValue), .text(i.category.rawValue), .text(i.contentHash),
            .opt(i.text), .text(i.preview), .opt(i.blobPath), .opt(i.thumbPath), .int(Int64(i.byteSize)),
            .opt(i.sourceBundle), .opt(i.sourceName),
            .double(i.createdAt.timeIntervalSince1970), .double(i.lastUsedAt.timeIntervalSince1970),
            .int(Int64(i.copyCount)), .int(i.pinned ? 1 : 0), .opt(i.pinOrder), .opt(i.expiresAt)])
    }

    public func item(withHash hash: String) throws -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT \(Self.cols) FROM clip_item WHERE content_hash = ?", [.text(hash)], map: Self.item).first
    }

    public func item(id: String) throws -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT \(Self.cols) FROM clip_item WHERE id = ?", [.text(id)], map: Self.item).first
    }

    /// Pinned first (by pin_order), then most recently used.
    public func all(limit: Int = 10_000) throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT \(Self.cols) FROM clip_item ORDER BY pinned DESC, pin_order ASC, last_used_at DESC LIMIT ?",
                            [.int(Int64(limit))], map: Self.item)
    }

    public func count() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT COUNT(*) FROM clip_item", map: { $0.int(0) }).first ?? 0
    }

    public func totalBytes() throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT COALESCE(SUM(byte_size),0) FROM clip_item", map: { $0.int(0) }).first ?? 0
    }

    public func setPinned(id: String, pinned: Bool, expiresAt: Date?) throws {
        lock.lock(); defer { lock.unlock() }
        try db.execute("UPDATE clip_item SET pinned = ?, expires_at = ?, pin_order = ? WHERE id = ?",
                       [.int(pinned ? 1 : 0), .opt(pinned ? nil : expiresAt),
                        pinned ? .int(Int64(Date().timeIntervalSince1970)) : .null, .text(id)])
    }

    public func touch(id: String, lastUsed: Date, createdAt: Date, expiresAt: Date?, pinned: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        // A re-copy is a fresh user action: reset the clock (unless pinned).
        try db.execute("""
        UPDATE clip_item SET last_used_at = ?, copy_count = copy_count + 1,
          created_at = CASE WHEN pinned = 1 THEN created_at ELSE ? END,
          expires_at = CASE WHEN pinned = 1 THEN NULL ELSE ? END WHERE id = ?
        """, [.double(lastUsed.timeIntervalSince1970), .double(createdAt.timeIntervalSince1970), .opt(expiresAt), .text(id)])
    }

    public func markUsed(id: String, at date: Date) throws {
        lock.lock(); defer { lock.unlock() }
        try db.execute("UPDATE clip_item SET last_used_at = ? WHERE id = ?", [.double(date.timeIntervalSince1970), .text(id)])
    }

    /// Recompute expiry for all unpinned items after a retention change.
    public func applyRetention(_ policy: RetentionPolicy) throws {
        lock.lock(); defer { lock.unlock() }
        if let interval = policy.interval {
            try db.execute("UPDATE clip_item SET expires_at = created_at + ? WHERE pinned = 0", [.double(interval)])
        } else {
            try db.execute("UPDATE clip_item SET expires_at = NULL WHERE pinned = 0")
        }
    }

    /// Deletes expired unpinned items; returns the removed items (so callers can remove blobs).
    public func deleteExpired(now: Date) throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        let gone = try db.query("SELECT \(Self.cols) FROM clip_item WHERE pinned = 0 AND expires_at IS NOT NULL AND expires_at < ?",
                                [.double(now.timeIntervalSince1970)], map: Self.item)
        if !gone.isEmpty {
            try db.execute("DELETE FROM clip_item WHERE pinned = 0 AND expires_at IS NOT NULL AND expires_at < ?",
                           [.double(now.timeIntervalSince1970)])
        }
        return gone
    }

    public func delete(id: String) throws -> ClipboardItem? {
        lock.lock(); defer { lock.unlock() }
        let it = try db.query("SELECT \(Self.cols) FROM clip_item WHERE id = ?", [.text(id)], map: Self.item).first
        try db.execute("DELETE FROM clip_item WHERE id = ?", [.text(id)])
        return it
    }

    public func deleteAll(includingPinned: Bool) throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        let sql = includingPinned ? "" : " WHERE pinned = 0"
        let gone = try db.query("SELECT \(Self.cols) FROM clip_item\(sql)", map: Self.item)
        try db.execute("DELETE FROM clip_item\(sql)")
        return gone
    }

    /// Oldest unpinned items beyond `max` count.
    public func unpinnedOverflow(maxItems: Int) throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT \(Self.cols) FROM clip_item WHERE pinned = 0 ORDER BY last_used_at DESC LIMIT -1 OFFSET ?",
                            [.int(Int64(maxItems))], map: Self.item)
    }

    /// Unpinned items, oldest first (for disk-budget eviction).
    public func unpinnedOldestFirst() throws -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        return try db.query("SELECT \(Self.cols) FROM clip_item WHERE pinned = 0 ORDER BY last_used_at ASC", map: Self.item)
    }

    public func checkpoint() {
        lock.lock(); defer { lock.unlock() }
        try? db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
}
