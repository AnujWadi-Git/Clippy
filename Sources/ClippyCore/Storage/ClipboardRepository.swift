import Foundation

/// Source of truth for the UI. Keeps the full history in memory (for instant panel open / search) and
/// mirrors every change to SQLite + BlobStore. Also holds short-lived in-memory-only sensitive items.
public final class ClipboardRepository: @unchecked Sendable {
    private let db: ClipboardDatabase
    public let blobs: BlobStore
    private let settings: SettingsManager
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var cache: [ClipboardItem] = []
    private var ephemeral: [ClipboardItem] = []
    public static let ephemeralLifetime: TimeInterval = 60

    /// Called (on an arbitrary thread) after any change.
    public var onChange: (@Sendable () -> Void)?

    public init(database: ClipboardDatabase, blobs: BlobStore, settings: SettingsManager,
                clock: @escaping @Sendable () -> Date = { Date() }) throws {
        self.db = database; self.blobs = blobs; self.settings = settings; self.clock = clock
        cache = try db.all()
    }

    /// Pinned first, then recent. Includes live ephemeral items at the top.
    public func snapshot() -> [ClipboardItem] {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        ephemeral.removeAll { ($0.expiresAt ?? now) < now }
        return ephemeral + cache
    }

    public func item(id: String) -> ClipboardItem? { snapshot().first { $0.id == id } }

    // MARK: Ingest

    public enum IngestResult: Equatable { case stored(ClipboardItem), duplicate(ClipboardItem) }

    public func ingest(_ draft: ClipboardItem) throws -> IngestResult {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        let now = clock()
        if let existing = cache.first(where: { $0.contentHash == draft.contentHash }) {
            if settings.ignoreDuplicates {
                // The user copied it again: a fresh copy, fresh retention window. (Never AI-driven.)
                let exp = existing.pinned ? nil : settings.retention.expiry(from: now)
                try db.touch(id: existing.id, lastUsed: now, createdAt: now, expiresAt: exp, pinned: existing.pinned)
                var u = existing
                u.lastUsedAt = now; u.copyCount += 1
                if !u.pinned { u.createdAt = now; u.expiresAt = exp }
                cache.removeAll { $0.id == u.id }
                insertSorted(u)
                if let blob = draft.blobPath, blob != u.blobPath { blobs.remove(blob); blobs.remove(draft.thumbPath) }
                return .duplicate(u)
            }
        }
        var item = draft
        item.createdAt = now; item.lastUsedAt = now
        item.expiresAt = settings.retention.expiry(from: now)
        if !settings.ignoreDuplicates, cache.contains(where: { $0.contentHash == item.contentHash }) {
            item.contentHash += "#" + UUID().uuidString
        }
        try db.insert(item)
        insertSorted(item)
        try enforceLimitsLocked()
        return .stored(item)
    }

    /// Hash-only lookup used before doing expensive work (image thumbnailing).
    public func exists(hash: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cache.contains { $0.contentHash == hash }
    }

    public func addEphemeral(_ draft: ClipboardItem) {
        lock.lock()
        var i = draft
        i.expiresAt = clock().addingTimeInterval(Self.ephemeralLifetime)
        ephemeral.removeAll { $0.contentHash == i.contentHash }
        ephemeral.insert(i, at: 0)
        lock.unlock(); onChange?()
    }

    private func insertSorted(_ item: ClipboardItem) {
        // cache order: pinned (by pinOrder) first, then lastUsedAt desc
        if item.pinned {
            cache.append(item)
        } else {
            let idx = cache.firstIndex { !$0.pinned && $0.lastUsedAt <= item.lastUsedAt } ?? cache.count
            cache.insert(item, at: idx)
        }
        if item.pinned { resortLocked() }
    }

    private func resortLocked() {
        cache.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if a.pinned { return (a.pinOrder ?? 0) < (b.pinOrder ?? 0) }
            return a.lastUsedAt > b.lastUsedAt
        }
    }

    // MARK: Mutations

    public func setPinned(id: String, _ pinned: Bool) throws {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        guard let idx = cache.firstIndex(where: { $0.id == id }) else { return }
        let now = clock()
        let exp = pinned ? nil : settings.retention.expiry(from: now)   // unpinning starts a fresh window
        try db.setPinned(id: id, pinned: pinned, expiresAt: exp)
        cache[idx].pinned = pinned
        cache[idx].expiresAt = exp
        cache[idx].pinOrder = pinned ? Int(now.timeIntervalSince1970) : nil
        if !pinned { cache[idx].createdAt = now }
        resortLocked()
    }

    public func markUsed(id: String) {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        guard let idx = cache.firstIndex(where: { $0.id == id }) else { return }
        let now = clock()
        try? db.markUsed(id: id, at: now)
        cache[idx].lastUsedAt = now
        if !cache[idx].pinned { var it = cache.remove(at: idx); it.lastUsedAt = now; insertSorted(it) }
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        ephemeral.removeAll { $0.id == id }
        if let it = try db.delete(id: id) { removeBlobs(it) }
        cache.removeAll { $0.id == id }
    }

    public func clear(includingPinned: Bool = false) throws {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        ephemeral.removeAll()
        for it in try db.deleteAll(includingPinned: includingPinned) { removeBlobs(it) }
        cache.removeAll { includingPinned || !$0.pinned }
        db.checkpoint()
    }

    public func applyRetention(_ policy: RetentionPolicy) throws {
        lock.lock()
        defer { lock.unlock(); onChange?() }
        try db.applyRetention(policy)
        for i in cache.indices where !cache[i].pinned { cache[i].expiresAt = policy.expiry(from: cache[i].createdAt) }
    }

    // MARK: Cleanup

    @discardableResult
    public func purgeExpired() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        ephemeral.removeAll { ($0.expiresAt ?? now) < now }
        let gone = try db.deleteExpired(now: now)
        for it in gone { removeBlobs(it) }
        var ids = Set(gone.map(\.id))
        cache.removeAll { ids.contains($0.id) }
        // Early cleanup of junk (can only shorten life, never extend it).
        var junkCount = 0
        if settings.cleanJunk {
            for it in cache where JunkDetector.isJunk(it, now: now) {
                _ = try? db.delete(id: it.id); removeBlobs(it); ids.insert(it.id); junkCount += 1
            }
            cache.removeAll { ids.contains($0.id) }
        }
        try enforceLimitsLocked()
        blobs.removeOrphans(keeping: Set(cache.flatMap { [$0.blobPath, $0.thumbPath].compactMap { $0 } }))
        if !gone.isEmpty || junkCount > 0 { db.checkpoint(); onChange?() }
        return gone.count + junkCount
    }

    /// Caller holds the lock.
    private func enforceLimitsLocked() throws {
        // 1. Max item count (oldest unpinned first).
        for it in try db.unpinnedOverflow(maxItems: settings.maxItems) {
            _ = try db.delete(id: it.id); removeBlobs(it); cache.removeAll { $0.id == it.id }
        }
        // 2. Disk budget (DB payload + blobs), evict oldest unpinned.
        var total = try db.totalBytes()
        if total > settings.maxDiskBytes {
            for it in try db.unpinnedOldestFirst() where total > settings.maxDiskBytes {
                total -= it.byteSize
                _ = try db.delete(id: it.id); removeBlobs(it); cache.removeAll { $0.id == it.id }
            }
        }
    }

    private func removeBlobs(_ it: ClipboardItem) { blobs.remove(it.blobPath); blobs.remove(it.thumbPath) }

    public var diskUsageBytes: Int { (try? db.totalBytes()) ?? 0 }
}
