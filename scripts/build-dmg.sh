#!/usr/bin/env bash
# Package build/ZTARC.app as a disk image.
#
# hdiutil only, which is on every Mac. Upstream releases are cut by hand with DMG
# Canvas.app, and its project file is deleted during staging: it hardcodes a path
# into a developer's home directory, their Apple ID and a notarization
# certificate hash, so it could not build here even with the app installed. What
# it bought was a background image and icon positions; what it cost was a GUI
# dependency in the release path. This is the trade the other way.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
. "$ROOT/scripts/brand.sh"
ztarc_brand
# shellcheck disable=SC1091
. "$ROOT/scripts/version.sh"
VERSION="$(ztarc_version)"

APP="$ROOT/build/$BRAND_NAME.app"
[ -d "$APP" ] || { echo "no build/$BRAND_NAME.app — run scripts/build-app.sh" >&2; exit 1; }

STAGE="$ROOT/build/dmgroot"
OUT="$ROOT/build/ztarc-$VERSION.dmg"

rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$BRAND_NAME.app"
ln -s /Applications "$STAGE/Applications"

# The licences ride along in the image. AGPL-3 obliges us to convey them with the
# binary, and .txt so a double click opens them in TextEdit rather than asking
# what to open them with.
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
[ -f "$ROOT/NOTICE" ] && cp "$ROOT/NOTICE" "$STAGE/NOTICE.txt"

echo "dmg    $BRAND_NAME $VERSION"
hdiutil create \
    -volname "$BRAND_NAME $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov -quiet "$OUT"

# The /Applications alias must survive as a symlink; if hdiutil ever dereferences
# it the image ships a copy of the user's Applications folder, which is both
# enormous and wrong. Cheap to check, catastrophic to miss.
MNT="$(hdiutil attach "$OUT" -nobrowse -noverify -noautoopen | grep -o '/Volumes/.*' | head -1)"
if [ ! -L "$MNT/Applications" ]; then
    hdiutil detach "$MNT" -quiet || true
    echo "the /Applications alias was not preserved as a symlink" >&2
    exit 1
fi
hdiutil detach "$MNT" -quiet

# Recorded as a bare filename, not a path. `shasum -a 256 "$OUT"` writes the
# absolute path it was built at, so the file published beside a release would
# name /Users/runner/work/... and `shasum -c` would fail for everyone who
# downloaded it — the one command the checksum exists to support.
( cd "$(dirname "$OUT")" && shasum -a 256 "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
cat "$OUT.sha256"
echo "→ $(basename "$OUT")"
