import Foundation
import CryptoKit

/// Exact-duplicate detection through SHA-256 of the canonical content.
public enum DuplicateDetector {
    public static func hash(text: String) -> String { hex(SHA256.hash(data: Data(("t:" + text).utf8))) }
    public static func hash(data: Data, kind: ClipKind) -> String {
        var h = SHA256()
        h.update(data: Data("\(kind.rawValue):".utf8)); h.update(data: data)
        return hex(h.finalize())
    }
    private static func hex<D: Digest>(_ d: D) -> String { d.map { String(format: "%02x", $0) }.joined() }
}
