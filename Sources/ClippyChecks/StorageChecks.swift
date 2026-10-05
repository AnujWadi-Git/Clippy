import Foundation
import CryptoKit
import ClippyCore

final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var t: Date
    init(_ t: Date = Date()) { self.t = t }
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: TimeInterval) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}

struct Env {
    let settings: SettingsManager, repo: ClipboardRepository, pipeline: CapturePipeline, clock: TestClock, dir: URL, db: ClipboardDatabase
    init(crypto: CryptoBox? = nil) throws {
        let suite = "clippy.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = SettingsManager(defaults: defaults)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-test-\(UUID().uuidString)")
        db = try ClipboardDatabase(path: ":memory:", crypto: crypto)
        clock = TestClock()
        let c = clock
        repo = try ClipboardRepository(database: db, blobs: try BlobStore(directory: dir), settings: settings, clock: { c.now })
        pipeline = CapturePipeline(repository: repo, settings: settings)
    }
    func copy(_ s: String, app: String? = nil, types: [String] = []) -> CaptureOutcome {
        pipeline.process(CapturedClip(payload: .text(s), pasteboardTypes: types, sourceBundle: app, sourceName: app))
    }
}

func storageChecks() {
    suite("Defaults") {
        let e = try Env()
        expect(e.settings.retention == .hour24, "default retention 24h")
        expect(e.settings.protectSensitive, "protect on by default")
        expect(!e.settings.allowCloudProcessing && !e.settings.aiEnabled, "cloud/AI off by default")
        expect(RetentionPolicy.hour24.interval == 86_400)
    }

    suite("Capture + dedupe") {
        let e = try Env()
        guard case .stored = e.copy("hello") else { expect(false, "stored"); return }
        e.clock.advance(10)
        guard case .duplicate = e.copy("hello") else { expect(false, "duplicate"); return }
        expect(e.repo.snapshot().count == 1, "one entry")
        expect(e.repo.snapshot()[0].copyCount == 2)
        _ = e.copy("world")
        e.clock.advance(5)
        _ = e.copy("hello")
        expect(e.repo.snapshot().map(\.preview) == ["hello", "world"], "dup bumps to top: \(e.repo.snapshot().map(\.preview))")
        expect(e.copy("   \n ") == .empty)
    }

    suite("24h expiry + cleanup") {
        let e = try Env()
        _ = e.copy("old thing"); _ = e.copy("pin me")
        let pinID = e.repo.snapshot().first { $0.preview == "pin me" }!.id
        try e.repo.setPinned(id: pinID, true)
        e.clock.advance(23 * 3600)
        expect(try e.repo.purgeExpired() == 0, "nothing at 23h")
        e.clock.advance(2 * 3600)
        expect(try e.repo.purgeExpired() == 1, "one expired at 25h")
        let left = e.repo.snapshot()
        expect(left.count == 1 && left[0].preview == "pin me" && left[0].pinned && left[0].expiresAt == nil, "pinned survives")
        // unpin → fresh window
        try e.repo.setPinned(id: pinID, false)
        expect(e.repo.snapshot()[0].expiresAt != nil)
        e.clock.advance(25 * 3600)
        expect(try e.repo.purgeExpired() == 1, "unpinned item expires after fresh window")
        expect(e.repo.snapshot().isEmpty)
    }

    suite("Re-copy resets window; retention change") {
        let e = try Env()
        _ = e.copy("x item")
        e.clock.advance(20 * 3600)
        _ = e.copy("x item")                // user copied again
        e.clock.advance(10 * 3600)          // 30h since first, 10h since second
        expect(try e.repo.purgeExpired() == 0, "re-copy is a new user action")
        e.settings.retention = .hour6
        try e.repo.applyRetention(.hour6)
        expect(try e.repo.purgeExpired() == 1, "shorter retention applies to existing items")
        _ = e.copy("forever"); e.settings.retention = .never; try e.repo.applyRetention(.never)
        e.clock.advance(365 * 86400)
        expect(try e.repo.purgeExpired() == 0, "never")
    }

    suite("Sensitive filtering in pipeline") {
        let e = try Env()
        if case .droppedSensitive(.awsKey) = e.copy("AKIAIOSFODNN7EXAMPLE") {} else { expect(false, "aws dropped") }
        if case .droppedSensitive(.concealedPasteboard) = e.copy("hunter2", types: ["org.nspasteboard.ConcealedType"]) {} else { expect(false, "concealed") }
        if case .droppedSensitive(.ignoredApp) = e.copy("anything", app: "com.1password.1password") {} else { expect(false, "1password") }
        expect(e.repo.snapshot().isEmpty, "nothing persisted")
        e.settings.sensitiveMode = .memoryOnly
        if case .heldInMemory = e.copy("482913") {} else { expect(false, "memory only") }
        expect(e.repo.snapshot().count == 1 && e.repo.snapshot()[0].preview.hasPrefix("🔒"))
        expect(e.repo.snapshot()[0].text == "482913" )
        let all = try e.db.all()
        expect(all.isEmpty, "never in db")
        e.clock.advance(61)
        expect(e.repo.snapshot().isEmpty, "ephemeral expires in 60s")
        e.settings.protectSensitive = false
        if case .stored = e.copy("AKIAIOSFODNN7EXAMPLE") {} else { expect(false, "stored when protection off") }
        // user-excluded apps
        e.settings.ignoredApps = ["com.example.secretapp"]
        expect(e.copy("fine text", app: "com.example.secretapp") == .ignoredApp)
    }

    suite("Pinned content encrypted at rest") {
        let box = CryptoBox(key: SymmetricKey(size: .bits256))
        let e = try Env(crypto: box)
        _ = e.copy("my home address 123 Main St")
        let id = e.repo.snapshot()[0].id
        try e.repo.setPinned(id: id, true)
        // Reading through db decrypts
        let viaDB = try e.db.item(id: id)
        expect(viaDB?.text == "my home address 123 Main St" && viaDB?.pinned == true)
        expect(viaDB?.preview == "my home address 123 Main St")
        // Raw box roundtrip + sealed form is not plaintext
        let sealed = box.seal("secret")
        expect(sealed != "secret" && CryptoBox.isSealed(sealed) && box.open(sealed) == "secret")
        try e.repo.setPinned(id: id, false)
        expect(try e.db.item(id: id)?.text == "my home address 123 Main St")
    }

    suite("Raw DB bytes of pinned items are ciphertext") {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("clippy-raw-\(UUID().uuidString).sqlite").path
        let db = try ClipboardDatabase(path: path, crypto: CryptoBox(key: SymmetricKey(size: .bits256)))
        let item = ClipboardItem(kind: .text, category: .message, contentHash: "h1", text: "TOP-SECRET-ADDRESS", preview: "TOP-SECRET-ADDRESS", byteSize: 18)
        try db.insert(item)
        try db.setPinned(id: item.id, pinned: true, expiresAt: nil)
        let raw = try SQLiteDatabase(path: path)
        let rows = try raw.query("SELECT text, preview FROM clip_item") { ($0.text(0) ?? "", $0.text(1) ?? "") }
        expect(rows.count == 1 && !rows[0].0.contains("TOP-SECRET") && !rows[0].1.contains("TOP-SECRET"), "raw: \(rows)")
        expect(rows.first?.0.hasPrefix("enc1:") == true)
        try? FileManager.default.removeItem(atPath: path)
    }

    suite("Limits") {
        let e = try Env()
        e.settings.maxItems = 5
        for i in 0..<9 { _ = e.copy("item number \(i)"); e.clock.advance(1) }
        expect(e.repo.snapshot().count == 5, "max items: \(e.repo.snapshot().count)")
        expect(e.repo.snapshot()[0].preview == "item number 8")
        let e2 = try Env()
        e2.settings.maxDiskMB = 0   // budget of zero bytes → evict everything unpinned
        _ = e2.copy("a long enough text"); 
        expect(e2.repo.snapshot().isEmpty, "disk budget evicts")
    }

    suite("Images + files") {
        let e = try Env()
        // 1x1 PNG
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        if case .stored = e.pipeline.process(CapturedClip(payload: .image(png))) {} else { expect(false, "image stored") }
        if case .duplicate = e.pipeline.process(CapturedClip(payload: .image(png))) {} else { expect(false, "image dup") }
        let it = e.repo.snapshot()[0]
        expect(it.kind == .image && it.blobPath != nil && e.repo.blobs.read(it.blobPath!) == png)
        expect(it.thumbPath != nil, "thumbnail")
        let files = try FileManager.default.contentsOfDirectory(atPath: e.dir.path)
        expect(files.count == 2, "orig+thumb only (dup wrote nothing): \(files.count)")
        if case .stored = e.pipeline.process(CapturedClip(payload: .files(["/tmp/a.txt", "/tmp/b.pdf"]))) {} else { expect(false, "files") }
        expect(e.repo.snapshot()[0].preview == "a.txt, b.pdf")
        try e.repo.delete(id: it.id)
        expect(try FileManager.default.contentsOfDirectory(atPath: e.dir.path).isEmpty, "blobs removed with item")
    }

    suite("Clear history keeps pins") {
        let e = try Env()
        _ = e.copy("one one"); _ = e.copy("two two")
        try e.repo.setPinned(id: e.repo.snapshot()[0].id, true)
        try e.repo.clear()
        expect(e.repo.snapshot().count == 1 && e.repo.snapshot()[0].pinned)
        try e.repo.clear(includingPinned: true)
        expect(e.repo.snapshot().isEmpty)
    }
}
