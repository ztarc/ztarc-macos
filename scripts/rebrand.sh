#!/usr/bin/env bash
# Stage upstream into build/src and make it ZTARC.
#
# upstream/ is read, never written — so `git -C upstream status` stays clean and
# moving to a new upstream release is a checkout, not a merge against our own
# edits. Everything here happens in a disposable copy.
#
# The order below is load-bearing:
#   1. patches   — context must match pristine upstream, so they run first
#   2. strip-ios — structural; must precede sed, so that afterwards the macOS
#                  target is the only one left and renaming it renames the .app
#   3. sed       — string substitutions, indifferent to line numbers
#   4. renames   — paths, to match the names sed just wrote into the project
#   5. overrides — whole files that are ours outright
#   6. assets    — icons and artwork
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/upstream"
DST="$ROOT/build/src"

# shellcheck disable=SC1091
. "$ROOT/scripts/brand.sh"
ztarc_brand

[ -f "$SRC/Pangolin.xcodeproj/project.pbxproj" ] || {
    echo "upstream/ is empty — run: git submodule update --init" >&2
    exit 1
}

echo "stage  upstream $(git -C "$SRC" describe --tags --always) -> build/src"
rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -a "$SRC" "$DST"
rm -rf "$DST/.git"

# Upstream's own docs and issue templates. Not built, not shipped, and full of
# the upstream vendor's name and support links — keeping them would mean either
# rewriting someone else's contribution terms, which would be dishonest, or
# carrying a pile of audit exemptions. LICENSE stays: AGPL-3 requires retaining
# upstream's attribution, and removing it would be the violation, not the fix.
rm -f "$DST/README.md" "$DST/CONTRIBUTING.md" "$DST/SECURITY.md"
rm -rf "$DST/.github"
# A repo-wide destructive rewrite of every Swift file. Upstream has already run
# it; running it again would rewrite files our patches depend on.
rm -f "$DST/remove-header-comments.sh"

# A DMG Canvas document: a GUI app's project file, carrying a hardcoded path into
# a developer's home directory, their Apple ID and a notarization certificate
# hash. It could not build here even with the app installed. scripts/build-dmg.sh
# replaces it with hdiutil, which is already on every Mac.
rm -rf "$DST/Pangolin_Installer.dmgcanvas"

# Onboarding screenshots with the upstream product's name and bundle id baked in
# as pixels. brand/patches/0002 removes the views that showed them; this removes
# the images, so they cannot reach Assets.car either. See that patch for why no
# amount of sed could have fixed these.
rm -rf "$DST/Pangolin/Assets.xcassets/AllowVPN.imageset" \
       "$DST/Pangolin/Assets.xcassets/InstallNetworkExtension.imageset"

# Upstream's app icon, an Icon Composer bundle containing a vector of their
# animal. brand/assets supplies a classic .appiconset in its place and
# brand/rules.sed points ASSETCATALOG_COMPILER_APPICON_NAME at it. Nothing here
# could have rebranded a .icon: its artwork is an SVG we have no equivalent of,
# and shipping the upstream vendor's mark as our app icon is the one substitution
# failure a user would notice before launching the app.
rm -rf "$DST/Pangolin/pangolin-app-icon.icon"

# ── 1. patches ────────────────────────────────────────────────────────────────
# Applied from the repository root with --directory, NOT with `git -C build/src`.
# build/src is inside this work tree, so `git apply` there resolves paths against
# the repository root rather than the current directory: it finds nothing to do
# and exits 0. ztarc-windows shipped a release that way once — the patches had
# silently stopped applying and nothing failed. scripts/audit-brand.sh asserts
# each patch's result for the same reason.
shopt -s nullglob
for patch in "$ROOT"/brand/patches/*.patch; do
    echo "patch  $(basename "$patch")"
    git -C "$ROOT" apply --directory="build/src" -p1 "$patch"
done
shopt -u nullglob

# ── 2. strip iOS ──────────────────────────────────────────────────────────────
echo "strip  iOS targets"
"$ROOT/scripts/strip-ios.py" "$DST/Pangolin.xcodeproj/project.pbxproj"
rm -rf "$DST/Pangolin/iOS" "$DST/PacketTunnel/iOS"
rm -f "$DST/Pangolin.xcodeproj/xcshareddata/xcschemes/PangoliniOS.xcscheme" \
      "$DST/Pangolin.xcodeproj/xcshareddata/xcschemes/PacketTunneliOS.xcscheme"

# ── 3. sed ────────────────────────────────────────────────────────────────────
# `sed -i -f` is GNU-only; BSD sed reads -i's argument as the suffix. Writing to
# a temporary and moving it behaves the same everywhere and needs no gsed.
echo "sed    brand/rules.sed"
find "$DST" \
    \( -name '*.swift' -o -name '*.plist' -o -name '*.entitlements' \
       -o -name 'project.pbxproj' -o -name '*.xcscheme' -o -name '*.go' \
       -o -name '*.sh' -o -name '*.json' -o -name '*.modulemap' \
       -o -name '*.nix' -o -name '*.h' -o -name '*.m' \) \
    -type f -print0 |
while IFS= read -r -d '' file; do
    sed -f "$ROOT/brand/rules.sed" "$file" > "$file.ztarc" && mv "$file.ztarc" "$file"
done

# ── 4. renames ────────────────────────────────────────────────────────────────
# sed has just written ZTARC into the project's paths; move the files to match.
# Source folders are PBXFileSystemSynchronizedRootGroups, so renaming a
# directory needs no further project edit beyond the `path =` sed already did.
echo "rename paths"
mv "$DST/Pangolin.xcodeproj" "$DST/$BRAND_NAME.xcodeproj"
mv "$DST/$BRAND_NAME.xcodeproj/xcshareddata/xcschemes/Pangolin.xcscheme" \
   "$DST/$BRAND_NAME.xcodeproj/xcshareddata/xcschemes/$BRAND_NAME.xcscheme"
mv "$DST/Pangolin" "$DST/$BRAND_NAME"
mv "$DST/$BRAND_NAME/macOS/Pangolin.entitlements" \
   "$DST/$BRAND_NAME/macOS/$BRAND_NAME.entitlements"
mv "$DST/$BRAND_NAME/macOS/PangolinApp.swift" \
   "$DST/$BRAND_NAME/macOS/${BRAND_NAME}App.swift"
mv "$DST/$BRAND_NAME/Assets.xcassets/PangolinLogo.imageset" \
   "$DST/$BRAND_NAME/Assets.xcassets/${BRAND_NAME}Logo.imageset"
mv "$DST/$BRAND_NAME/Assets.xcassets/PangolinMenuBarIcon.imageset" \
   "$DST/$BRAND_NAME/Assets.xcassets/${BRAND_NAME}MenuBarIcon.imageset"
mv "$DST/$BRAND_NAME/Assets.xcassets/${BRAND_NAME}MenuBarIcon.imageset/PangolinMenuBarIcon.png" \
   "$DST/$BRAND_NAME/Assets.xcassets/${BRAND_NAME}MenuBarIcon.imageset/${BRAND_NAME}MenuBarIcon.png"
for f in "$DST/$BRAND_NAME/Assets.xcassets/${BRAND_NAME}Logo.imageset/"pangolin-logo-*.png; do
    mv "$f" "${f/pangolin-logo-/ztarc-logo-}"
done

# ── 4b. version ───────────────────────────────────────────────────────────────
# Stamped from brand/version.env so the .app's properties, the DMG filename and
# the release tag cannot state three different numbers. Upstream's macOS and iOS
# targets disagreed about the version (0.11.1 vs 0.10.0); one value now covers
# everything that is left.
# shellcheck disable=SC1091
. "$ROOT/scripts/version.sh"
# shellcheck disable=SC1091
. "$ROOT/brand/version.env"
VERSION="$(ztarc_version)"
echo "stamp  version $VERSION"
PBX="$DST/$BRAND_NAME.xcodeproj/project.pbxproj"
sed -e "s|MARKETING_VERSION = [0-9.]*;|MARKETING_VERSION = $VERSION;|g" \
    -e "s|CURRENT_PROJECT_VERSION = [0-9.]*;|CURRENT_PROJECT_VERSION = $BUILD;|g" \
    "$PBX" > "$PBX.ztarc" && mv "$PBX.ztarc" "$PBX"

# ── 5. overrides ──────────────────────────────────────────────────────────────
if [ -d "$ROOT/brand/overrides" ]; then
    (cd "$ROOT/brand/overrides" && find . -type f -print0) |
    while IFS= read -r -d '' rel; do
        echo "over   ${rel#./}"
        mkdir -p "$(dirname "$DST/${rel#./}")"
        cp "$ROOT/brand/overrides/${rel#./}" "$DST/${rel#./}"
    done
fi

# ── 6. assets ─────────────────────────────────────────────────────────────────
if [ -d "$ROOT/brand/assets" ]; then
    (cd "$ROOT/brand/assets" && find . -type f -print0) |
    while IFS= read -r -d '' rel; do
        echo "asset  ${rel#./}"
        mkdir -p "$(dirname "$DST/${rel#./}")"
        cp "$ROOT/brand/assets/${rel#./}" "$DST/${rel#./}"
    done
fi

# The licences travel with the build: AGPL-3 obliges us to convey them, and
# build-dmg.sh puts them in the disk image beside the app.
cp "$ROOT/LICENSE" "$DST/LICENSE.txt"
[ -f "$ROOT/NOTICE" ] && cp "$ROOT/NOTICE" "$DST/NOTICE.txt"

echo "staged $DST"
