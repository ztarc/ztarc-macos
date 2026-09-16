#!/usr/bin/env bash
# Build ZTARC.app from the staged, branded tree.
#
# Two steps that must happen in this order. The Go core is a c-archive built by
# upstream's own Makefile and linked in via LIBRARY_SEARCH_PATHS/-lpangolin;
# there is no shell-script build phase in the Xcode project, so nothing makes
# xcodebuild wait for it. Running xcodebuild first fails at link time with a
# missing-symbol error that says nothing about Go.
#
# Signing is passed as command-line overrides rather than written into the staged
# project, so the tree stays signing-agnostic and turning on a real identity is
# setting environment variables, not editing anything. See the block below.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$ROOT/build/src"

# shellcheck disable=SC1091
. "$ROOT/scripts/brand.sh"
ztarc_brand

[ -d "$DST" ] || { echo "nothing staged — run scripts/rebrand.sh" >&2; exit 1; }

command -v go >/dev/null || {
    echo "go is not installed. The client's core is Go built as a c-archive;" >&2
    echo "see upstream/PangolinGo/.go-version for the version." >&2
    exit 1
}
xcodebuild -version >/dev/null 2>&1 || {
    echo "xcodebuild is not usable. This needs full Xcode, not Command Line Tools:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    echo "The project is objectVersion 77 and its app icon is an Icon Composer" >&2
    echo "bundle, so it needs Xcode 26 or newer." >&2
    exit 1
}

# ── Go core ───────────────────────────────────────────────────────────────────
# BUILDDIR must stay RELATIVE. Upstream computes GOROOT_ABS := $(CURDIR)/$(GOROOT),
# so an absolute BUILDDIR produces build/src//abs/path/goroot and silently builds
# against the wrong toolchain. Pointing it outside build/src means the ~1GB
# patched-GOROOT rsync survives the next rebrand, which wipes build/src.
echo "go     building libpangolin (universal)"
make -C "$DST" build-macos BUILDDIR=../../.cache/go

# ── App ───────────────────────────────────────────────────────────────────────
# Ad-hoc ("-"), not CODE_SIGNING_ALLOWED=NO. An arm64 binary with no signature at
# all will not execute, so "unsigned" here has to mean ad-hoc signed. Ad-hoc also
# still applies the entitlements plist, so `codesign -d --entitlements -` shows
# what a signed build would carry — the unsigned build stays a faithful rehearsal
# of the real one rather than a differently-shaped thing.
#
# The system extension will NOT load like this: macOS validates the restricted
# com.apple.developer.* entitlements against a provisioning profile or the
# signing certificate, and ad-hoc has neither. The app launches and every branded
# surface is real; the tunnel is unreachable. See README.
: "${ZTARC_CODE_SIGN_IDENTITY:=-}"
: "${ZTARC_TEAM_ID:=}"
: "${ZTARC_PROVISIONING_PROFILE:=}"
: "${ZTARC_HARDENED_RUNTIME:=NO}"
: "${ZTARC_BUILD_ACTION:=build}"

DERIVED="$ROOT/build/dd"
echo "xcode  $BRAND_NAME.app (identity: $ZTARC_CODE_SIGN_IDENTITY)"
set -o pipefail
NSUnbufferedIO=YES xcodebuild \
    -project "$DST/$BRAND_NAME.xcodeproj" \
    -scheme "$BRAND_NAME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -clonedSourcePackagesDirPath "$ROOT/.cache/spm" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$ZTARC_CODE_SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$ZTARC_TEAM_ID" \
    PROVISIONING_PROFILE_SPECIFIER="$ZTARC_PROVISIONING_PROFILE" \
    ENABLE_HARDENED_RUNTIME="$ZTARC_HARDENED_RUNTIME" \
    "$ZTARC_BUILD_ACTION" 2>&1 | tee "$ROOT/build/xcodebuild.log"

APP="$DERIVED/Build/Products/Release/$BRAND_NAME.app"
[ -d "$APP" ] || { echo "xcodebuild reported success but produced no $BRAND_NAME.app" >&2; exit 1; }

# ditto, not cp -R: bundles carry extended attributes and symlink structure that
# cp does not reliably preserve.
rm -rf "$ROOT/build/$BRAND_NAME.app"
ditto "$APP" "$ROOT/build/$BRAND_NAME.app"

echo "→ build/$BRAND_NAME.app  ($(lipo -archs "$ROOT/build/$BRAND_NAME.app/Contents/MacOS/$BRAND_NAME" 2>/dev/null || echo 'arch unknown'))"
