# Installing Clippy

**Requirements:** macOS 14 or later, Apple silicon. On-device AI features (smart search refinement, rewrite, summarize…) need
macOS 26 with Apple Intelligence turned on; without it Clippy still works as a clipboard manager.

## From the DMG
1. Open `Clippy.dmg` and drag **Clippy** to **Applications**.
2. First launch: macOS blocks apps that aren't notarized. **Right-click Clippy → Open → Open.**
   (Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Clippy.app`.)
3. Follow the welcome dialog: tick *Launch at login*, and grant **Accessibility** so Clippy can paste into other apps.
4. If macOS asks whether Clippy may paste from other apps, choose **Allow**.
5. Press **⌥V** anywhere. Clippy lives in the menu bar (no Dock icon).

## From source
```bash
git clone git@github.com:AnujWadi-Git/Clippy.git && cd Clippy
Scripts/install.sh        # builds a release app, installs to /Applications, launches it
```
Needs only the Xcode Command Line Tools (`xcode-select --install`).

## Keys
⌥V open · ↑↓ move · ↩ paste · ⌥↩ plain text · ⌘↩ copy only · ⌘K actions · ⌘P pin · ⌘E mark (merge-paste) · ⌘⌫ delete ·
⌘1–9 quick paste · ⇥ filters · `?` ask · `>` commands · ⌥⇧V skip my next copy.

## Privacy in one paragraph
Everything stays on your Mac. Clips are deleted after 24 hours (configurable) unless pinned; pinned text is encrypted at rest.
Passwords, tokens, keys, cards and one-time codes are filtered out before anything is saved. AI runs on-device; cloud AI is
off unless you turn it on and add a key.

## Uninstall
Quit Clippy, delete `/Applications/Clippy.app`, and remove `~/Library/Application Support/Clippy`.
