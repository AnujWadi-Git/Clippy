#!/bin/bash
# Packages dist/Clippy.app into dist/Clippy.dmg with an /Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d dist/Clippy.app ] || Scripts/bundle.sh release
rm -rf dist/dmg dist/Clippy.dmg
mkdir -p dist/dmg
cp -R dist/Clippy.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname Clippy -srcfolder dist/dmg -ov -format UDZO dist/Clippy.dmg >/dev/null
rm -rf dist/dmg
echo "Built dist/Clippy.dmg"
