#!/usr/bin/env bash
# Regenerate brand/assets from the ZTARC mark.
#
# Output is committed, so this only needs running when the artwork itself
# changes. It is here so that "where did these PNGs come from" has an answer
# other than someone's Downloads folder.
#
# Source is ztarc-windows/brand/icons, which is where the ZTARC mark and wordmark
# already live as committed artwork for the Windows client. Using the same files
# is the point: two clients that disagree about the logo are worse than one
# client with no logo. Override with LOGO_DIR if the marks move to their own repo.
#
# Needs only python3 and sips, both of which ship with macOS. The Windows
# equivalent of this script needs ImageMagick; that was a real obstacle on a
# fresh machine, and none of what happens here justifies it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGO_DIR="${LOGO_DIR:-$ROOT/../ztarc-windows/brand/icons}"

# shellcheck disable=SC1091
. "$ROOT/scripts/brand.sh"
ztarc_brand

[ -f "$LOGO_DIR/icon-orange.ico" ] || {
    echo "no icon-orange.ico in $LOGO_DIR" >&2
    echo "Set LOGO_DIR to wherever the ZTARC marks live." >&2
    exit 1
}

OUT="$ROOT/brand/assets/$BRAND_NAME/Assets.xcassets"
rm -rf "$ROOT/brand/assets/$BRAND_NAME"
mkdir -p "$OUT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

python3 "$ROOT/scripts/make-icons.py" "$LOGO_DIR" "$OUT" "$WORK" "$BRAND_NAME"

echo "→ brand/assets/$BRAND_NAME/Assets.xcassets"
