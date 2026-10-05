import Foundation
import CryptoKit
import ClippyCore

func richTextChecks() {
    let rtf = Data("{\\rtf1\\ansi {\\b Hello bold secret-ish marker}}".utf8)
    let html = Data("<b>Hello bold</b> <a href=\"https://example.com\">link</a>".utf8)
    let box = CryptoBox(key: SymmetricKey(size: .bits256))

    suite("Rich text is kept, encrypted on disk") {
        let e = try Env(crypto: box)
        _ = e.copy("Hello bold link", rich: ["public.rtf": rtf, "public.html": html, "com.example.private": Data([9, 9])])
        let it = e.repo.snapshot()[0]
        expect(it.richPath != nil, "richPath set")
        let raw = e.repo.blobs.read(it.richPath!)!
        expect(raw.range(of: Data("bold".utf8)) == nil && raw.range(of: Data("rtf1".utf8)) == nil, "blob on disk is ciphertext")
        let back = RichContent.decode(e.repo.blobs.readSealed(it.richPath!)!)
        expect(back?["public.rtf"] == rtf && back?["public.html"] == html && back?["com.example.private"] == nil, "round trip; private types dropped")
        expect(it.byteSize > "Hello bold link".utf8.count, "formatting counts toward the disk budget")
        try e.repo.delete(id: it.id)
        expect(try FileManager.default.contentsOfDirectory(atPath: e.dir.path).isEmpty, "blob removed with item")
    }
    suite("Rich text switches and limits") {
        let e = try Env(crypto: box)
        e.settings.keepFormatting = false
        _ = e.copy("no formatting kept here", rich: ["public.rtf": rtf])
        expect(e.repo.snapshot()[0].richPath == nil, "setting off → plain only")
        e.settings.keepFormatting = true
        _ = e.copy("too large to keep", rich: ["public.rtf": Data(repeating: 65, count: RichContent.maxBytes + 1)])
        expect(e.repo.snapshot()[0].richPath == nil, "oversized formatting skipped")
        let noKey = try Env(crypto: nil)
        _ = noKey.copy("no encryption key available", rich: ["public.rtf": rtf])
        expect(noKey.repo.snapshot()[0].richPath == nil, "never stored unencrypted")
    }
    suite("Secrets hidden in formatting are not stored") {
        let e = try Env(crypto: box)
        let hidden = Data("<b>Visible words</b><span style=\"display:none\">AKIAIOSFODNN7EXAMPLE</span>".utf8)
        _ = e.copy("Visible words here", rich: ["public.html": hidden])
        expect(e.repo.snapshot().count == 1 && e.repo.snapshot()[0].richPath == nil, "plain text kept, formatting discarded")
    }

    suite("Rich text lifecycle") {
        let e = try Env(crypto: box)
        _ = e.copy("same words twice")                              // plain first
        e.clock.advance(5)
        _ = e.copy("same words twice", rich: ["public.html": html]) // formatted later
        expect(e.repo.snapshot().count == 1 && e.repo.snapshot()[0].richPath != nil, "duplicate adopts formatting")
        e.clock.advance(5)
        _ = e.copy("same words twice", rich: ["public.rtf": rtf])   // another formatted copy: keep the first
        let files = try FileManager.default.contentsOfDirectory(atPath: e.dir.path)
        expect(files.count == 1, "no leaked blobs: \(files.count)")
        e.clock.advance(25 * 3600)
        expect(try e.repo.purgeExpired() == 1)
        expect(try FileManager.default.contentsOfDirectory(atPath: e.dir.path).isEmpty, "expiry removes the blob")
        // pinned text with formatting: text sealed in DB AND blob sealed
        let p = try Env(crypto: box)
        _ = p.copy("pinned formatted words", rich: ["public.rtf": rtf])
        try p.repo.setPinned(id: p.repo.snapshot()[0].id, true)
        p.clock.advance(400 * 3600)
        expect(try p.repo.purgeExpired() == 0 && p.repo.snapshot()[0].richPath != nil, "pinned keeps formatting")
    }
}
