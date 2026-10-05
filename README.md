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
