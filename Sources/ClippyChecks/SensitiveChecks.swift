import Foundation
import ClippyCore

func sensitiveChecks() {
    let d = SensitiveContentDetector()
    func sensitive(_ s: String, _ r: SensitiveReason? = nil, line: Int = #line) {
        let v = d.check(text: s)
        expect(v != nil, "expected sensitive: \(s.prefix(40))", line: line)
        if let r { expect(v?.reason == r, "wrong reason \(String(describing: v?.reason)) for \(s.prefix(40))", line: line) }
    }
    func safe(_ s: String, line: Int = #line) {
        expect(d.check(text: s) == nil, "false positive (\(String(describing: d.check(text: s)?.reason))): \(s.prefix(60))", line: line)
    }

    suite("SensitiveContentDetector positives") {
        sensitive("-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----", .privateKey)
        sensitive("AKIAIOSFODNN7EXAMPLE", .awsKey)
        sensitive("ghp_" + String(repeating: "a1B2", count: 9), .apiToken)
        sensitive("xoxb-123456789012-abcdefghijkl", .apiToken)
        sensitive("sk-ant-api03-" + String(repeating: "Ab3_", count: 8), .apiToken)
        sensitive("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", .jwt)
        sensitive("postgres://admin:hunter2secret@db.example.com:5432/app", .credentialURL)
        sensitive("Authorization: Bearer abc123def456", .credentialAssignment)
        sensitive("password = Tr0ub4dor&3xyz", .credentialAssignment)
        sensitive("API_KEY=9f8e7d6c5b4a", .credentialAssignment)
        sensitive("4111 1111 1111 1111", .creditCard)
        sensitive("378282246310005", .creditCard)
        sensitive("482913", .otp)
        sensitive("123-456", .otp)
        sensitive("abandon ability able about above absent absorb abstract absurd abuse access accident", .seedPhrase)
        sensitive("Zx9$kLm2#Qp7vWn4&Rt8Yb3!", .highEntropy)
    }
    suite("SensitiveContentDetector negatives") {
        safe("hello world")
        safe("docker compose up -d")
        safe("https://github.com/AnujWadi-Git/Clippy")
        safe("https://docs.docker.com/engine/reference/commandline/build/")
        safe("550e8400-e29b-41d4-a716-446655440000")
        safe("a3f5c9d2e1b0")
        safe("3f786850e387550fdab836ed7e6dc881de23001b")
        safe("4111 1111 1111 1112")
        safe("+1 (415) 555-2671")
        safe("1234567890123")
        safe("/Users/anuj/Documents/Some Folder/file.txt")
        safe("hey can u send that file i need it rn")
        safe("let password = readLine()")
        safe("password: $PASSWORD")
        safe("the quick brown fox jumps over the lazy dog and runs far away from here today")
        safe("user@example.com")
        safe("12345678901")
        for n in ["8080", "2026", "12345", "94105"] { safe(n) }   // ports, years, ZIPs are not one-time codes
        safe("{\"name\": \"clippy\", \"version\": \"0.1.0\"}")
    }
    suite("SensitiveContentDetector metadata") {
        expect(d.checkMetadata(pasteboardTypes: ["org.nspasteboard.ConcealedType"], sourceBundle: nil)?.reason == .concealedPasteboard)
        expect(d.checkMetadata(pasteboardTypes: [], sourceBundle: "com.bitwarden.desktop")?.reason == .ignoredApp)
        expect(d.checkMetadata(pasteboardTypes: ["public.utf8-plain-text"], sourceBundle: "com.apple.Safari") == nil)
    }
}
