#!/bin/bash
# Builds a release Clippy.app and installs it to /Applications (falls back to ~/Applications), then launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle.sh release
DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
pkill -x Clippy 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Clippy.app"
cp -R dist/Clippy.app "$DEST/Clippy.app"
xattr -dr com.apple.quarantine "$DEST/Clippy.app" 2>/dev/null || true
open "$DEST/Clippy.app"
echo "Installed to $DEST/Clippy.app — look for the clipboard icon in the menu bar, press ⌥V."
