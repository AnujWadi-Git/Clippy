#!/bin/bash
# Builds Clippy.dmg and copies it (plus the version/size shown on the page) into the website folder.
# Then upload the website folder to Cloudflare Pages. Usage: Scripts/publish-to-site.sh [site-folder]
set -euo pipefail
cd "$(dirname "$0")/.."
SITE="${1:-$HOME/Downloads/Website/Latest/Cloudflare Upload - WORKING COPY}"
[ -d "$SITE/clippy" ] || { echo "No clippy/ folder in: $SITE"; exit 1; }
Scripts/bundle.sh release
Scripts/make-dmg.sh
cp dist/Clippy.dmg "$SITE/clippy/Clippy.dmg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Scripts/Info.plist)
SIZE=$(du -k dist/Clippy.dmg | awk '{printf "%.1f MB", $1/1024}')
python3 - "$SITE/clippy/index.html" "$VERSION" "$SIZE" <<'PY'
import re, sys
p, v, s = sys.argv[1:]
t = open(p).read()
t = re.sub(r'<span>v[0-9.]+</span><span>[0-9.]+ MB</span>', f'<span>v{v}</span><span>{s}</span>', t)
open(p, 'w').write(t)
PY
echo "Updated $SITE/clippy (v$VERSION, $SIZE). Now upload the site folder to Cloudflare Pages."
