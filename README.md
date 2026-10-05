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

## Status — v0.1 MVP + v1 AI

**Clipboard core:** monitor (text/URL/image/files), 24h retention + cleanup worker, SHA-256 dedupe, sensitive-content filtering
*before* persistence, deterministic categories, instant search + filters, pinning (pinned text encrypted at rest), ⌥V floating
panel with keyboard navigation, menu bar, Settings, Launch at Login, ignored apps, size limits.

**AI (user-triggered, on-device first):**
- **Smart search** — type a sentence or start with `?`: *“that command for starting my docker containers”*. Hybrid of intent parsing
  (type/time words), keywords and on-device embeddings; an optional on-device LLM only re-orders candidates. Search can only
  return items that exist; otherwise it says “No matching clipboard item found.”
- **Command mode** — type `>` then `summarize`, `rewrite professional`, `json format`, `explain`, `translate french`…
- **⌘K actions** — per-type: JSON pretty/minify/validate, link domain / strip tracking, run command in Terminal (confirmed),
  compose email, rewrite / shorten / expand / fix grammar / translate / summarize / explain / convert code (AI).
  Results become a new clipboard item, copied and ready to paste.
- **Pin suggestions** (copied ≥5×), **similar-item grouping** (`+N`, → to expand), **junk cleanup** (can only delete sooner, never extend).
- **Cloud AI is off by default.** If you enable it and add a key (stored in Keychain), only the single item you act on is
  sent, and only when on-device AI is unavailable (or you turn off “Prefer on-device”). Sensitive items are never sent anywhere.

### Verification
```bash
swift run ClippyChecks            # 260 checks on the core (add --live-ai to exercise the on-device model)
swift build && CLIPPY_DATA_DIR=/tmp/cs CLIPPY_DEFAULTS_SUITE=cs .build/debug/Clippy --selftest   # 29 headless end-to-end checks
```
Live-verified: pasteboard capture, classification, dedupe, sensitive dropping, semantic queries, command mode, transforms, and a
real on-device rewrite. **Not verified visually or interactively on a desktop:** panel appearance, the ⌥V hotkey, real keystrokes,
auto-paste (needs Accessibility), menu bar and Settings windows. Please try those and report anything off.

### Known limits
- On-device embeddings are modest; raw semantic ranking was only ~half right in my tests, so retrieval leans on intent parsing and
  keywords, with embeddings as a supporting signal (see docs/DESIGN.md).
- LLM prompt-injection defenses are best-effort; AI output is never executed automatically.
- “Summarize Page” for links is intentionally not offered (it would need Clippy to fetch the URL).
- Toolchain: only the Command Line Tools are needed. XCTest/swift-testing and SwiftUI’s `@State` need full Xcode, so tests are a
  plain executable and views use `@StateObject`.
