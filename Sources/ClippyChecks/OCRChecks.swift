import Foundation
import AppKit
import ClippyCore

/// Renders `text` black-on-white into PNG data (a stand-in for a screenshot).
func renderTextImage(_ text: String, size: NSSize = NSSize(width: 900, height: 140), font: CGFloat = 44) -> Data {
    let img = NSImage(size: size)
    img.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
    (text as NSString).draw(at: NSPoint(x: 24, y: size.height / 2 - font / 2),
                            withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: .medium), .foregroundColor: NSColor.black])
    img.unlockFocus()
    return NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}

func ocrChecks() {
    suite("ImageOCR") {
        let text = ImageOCR.recognize(renderTextImage("Invoice 4821 total due"))
        expect(text?.contains("Invoice") == true && text?.contains("4821") == true, "OCR read: \(String(describing: text))")
        expect(ImageOCR.recognize(Data([1, 2, 3])) == nil, "garbage → nil")
        let blank = NSImage(size: NSSize(width: 200, height: 100)); blank.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: 100).fill(); blank.unlockFocus()
        let blankPNG = NSBitmapImageRep(data: blank.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        expect(ImageOCR.recognize(blankPNG) == nil, "blank image → nil")
    }
    suite("Image capture with OCR") {
        let e = try Env()
        let png = renderTextImage("Quarterly report draft")
        guard case .stored = e.pipeline.process(CapturedClip(payload: .image(png))) else { expect(false, "stored"); return }
        let it = e.repo.snapshot()[0]
        expect(it.preview.hasPrefix("Image · ") && it.preview.contains("Quarterly"), "preview: \(it.preview)")
        expect(it.text?.contains("report") == true, "OCR text stored for search")
        expect(SearchEngine().search(e.repo.snapshot(), query: "quarterly").count == 1, "screenshot findable by its text")
        e.settings.ocrImages = false
        let png2 = renderTextImage("Another screenshot here")
        _ = e.pipeline.process(CapturedClip(payload: .image(png2)))
        expect(e.repo.snapshot()[0].text == nil && e.repo.snapshot()[0].preview == "Image", "OCR off → no text")
    }
    suite("Screenshot of a secret is dropped") {
        let e = try Env()
        let secret = renderTextImage("AKIAIOSFODNN7EXAMPLE", font: 52)
        let r = e.pipeline.process(CapturedClip(payload: .image(secret)))
        if case .droppedSensitive = r {} else { expect(false, "AWS key screenshot must be dropped, got \(r)") }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: e.dir.path)
        expect(e.repo.snapshot().isEmpty && leftovers.isEmpty, "nothing stored, no blob written")
        e.settings.protectSensitive = false
        if case .stored = e.pipeline.process(CapturedClip(payload: .image(secret))) {} else { expect(false, "stored when protection is off") }
    }
}
