# Clippy

**Copy once. Find it again.** A native macOS clipboard history (think Win+V) that remembers enough to be useful and forgets quickly enough to stay private.

- Press **⌥V** anywhere for the floating clipboard panel
- 24-hour retention by default (pinned items excepted), configurable
- Sensitive content (passwords, tokens, keys, cards, OTPs) is filtered *before* it's saved
- 100% local; no network unless you opt into cloud AI (future)

See [docs/DESIGN.md](docs/DESIGN.md) for the full design.

## Build & run
```bash
swift test
Scripts/bundle.sh debug && open dist/Clippy.app
```
Auto-paste needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility).
Without it Clippy copies the item and you press ⌘V.

## Status — v0.1 MVP (no AI yet)
Implemented: clipboard monitor (text/URL/image/files), 24h retention + cleanup worker, dedupe (SHA-256), sensitive-content
filtering before persistence, deterministic categories, instant search + filters, pinning (pinned text encrypted at rest),
⌥V floating panel with keyboard navigation, ⌘K actions, menu bar, Settings, Launch at Login, ignored apps, size limits.

Verification: `swift run ClippyChecks` runs 125 checks on the core (detector, classifier, search, retention, dedupe, limits,
encryption). Live-verified against the real pasteboard: capture, classification, 24h expiry stamp, dedupe, and dropping of
AWS keys / OTPs. **Not yet verified on a real desktop:** the panel's appearance, ⌥V hotkey, keyboard handling, auto-paste
(needs Accessibility), menu bar and Settings UI. Treat those as untested until you've tried them.

Toolchain note: only the Command Line Tools are required. XCTest/swift-testing and SwiftUI's `@State` macro need full Xcode,
so tests are a plain executable (`ClippyChecks`) and views use `@StateObject`.

Next: v1 AI (see docs/DESIGN.md §3, §9).
