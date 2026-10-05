import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Files for images (originals + thumbnails). Deleted files are zero-filled first.
public final class BlobStore: @unchecked Sendable {
    public let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) throws {
        self.directory = directory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var u = directory; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? u.setResourceValues(v)
    }

    /// Writes data; returns the file name (relative to `directory`).
    public func write(_ data: Data, ext: String = "png") throws -> String {
        let name = "\(UUID().uuidString).\(ext)"
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return name
    }

    public func read(_ name: String) -> Data? { try? Data(contentsOf: directory.appendingPathComponent(name)) }
    public func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    public func remove(_ name: String?) {
        guard let name else { return }
        let url = directory.appendingPathComponent(name)
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int), size > 0, size < 50_000_000,
           let h = try? FileHandle(forWritingTo: url) {
            try? h.write(contentsOf: Data(count: size)); try? h.synchronize(); try? h.close()
        }
        try? fm.removeItem(at: url)
    }

    /// Delete any file in the directory that no item references.
    public func removeOrphans(keeping referenced: Set<String>) {
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        for n in names where !referenced.contains(n) { remove(n) }
    }

    public func makeThumbnail(from data: Data, maxPixel: Int = 256) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: maxPixel]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
