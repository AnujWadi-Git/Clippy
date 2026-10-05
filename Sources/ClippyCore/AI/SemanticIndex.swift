import Foundation

/// In-memory vectors for fast semantic search, mirrored to SQLite for UNPINNED items only
/// (pinned items are encrypted at rest, so their vectors are recomputed in memory instead of persisted).
public final class SemanticIndex: @unchecked Sendable {
    private let db: ClipboardDatabase
    private let provider: EmbeddingProvider?
    private let lock = NSLock()
    private var vectors: [String: [Float]] = [:]
    private var persisted = Set<String>()

    public init(database: ClipboardDatabase, provider: EmbeddingProvider?) {
        db = database; self.provider = provider
        if let p = provider, let stored = try? db.loadEmbeddings(model: p.modelID) {
            vectors = stored; persisted = Set(stored.keys)
        }
    }

    public var isAvailable: Bool { provider != nil }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return vectors.count }

    public func embedQuery(_ q: String) -> [Float]? { provider?.embed(q) }

    public func vector(for id: String) -> [Float]? { lock.lock(); defer { lock.unlock() }; return vectors[id] }

    /// Embeds up to `limit` not-yet-indexed items; drops vectors for items that no longer exist or became pinned on disk.
    /// Cheap enough to run on a utility queue after changes. Returns how many were embedded.
    @discardableResult
    public func reconcile(items: [ClipboardItem], limit: Int = 60) -> Int {
        guard let provider else { return 0 }
        let alive = Set(items.map(\.id))
        let pinned = Set(items.filter(\.pinned).map(\.id))

        lock.lock()
        let gone = vectors.keys.filter { !alive.contains($0) }
        for id in gone { vectors[id] = nil; persisted.remove(id) }
        let toUnpersist = persisted.intersection(pinned)
        persisted.subtract(toUnpersist)
        lock.unlock()
        if !toUnpersist.isEmpty { try? db.deleteEmbeddings(ids: Array(toUnpersist)) }

        var done = 0
        for item in items where done < limit {
            lock.lock(); let has = vectors[item.id] != nil; let isPersisted = persisted.contains(item.id); lock.unlock()
            if has {
                if !isPersisted, !item.pinned, let v = vector(for: item.id) {   // e.g. just unpinned
                    try? db.saveEmbedding(id: item.id, model: provider.modelID, vector: v)
                    lock.lock(); persisted.insert(item.id); lock.unlock()
                }
                continue
            }
            guard let text = EmbeddingText.describe(item), let v = provider.embed(text) else { continue }
            lock.lock(); vectors[item.id] = v; lock.unlock()
            if !item.pinned {
                try? db.saveEmbedding(id: item.id, model: provider.modelID, vector: v)
                lock.lock(); persisted.insert(item.id); lock.unlock()
            }
            done += 1
        }
        return done
    }

    /// Remove everything (used when the user turns semantic search off).
    public func purge() {
        lock.lock(); vectors.removeAll(); persisted.removeAll(); lock.unlock()
        try? db.deleteAllEmbeddings()
    }
}
