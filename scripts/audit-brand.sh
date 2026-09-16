#!/usr/bin/env bash
# Refuse to build anything that still calls itself by the upstream name.
#
# This is the gate, and it is the reason the staging approach is safe at all.
# A sed rule that stops matching after an upstream bump fails silently: nothing
# errors, and a ZTARC-named binary greets people under someone else's name.
#
# Absence of the upstream name proves nothing on its own, either. A substitution
# that targets a *behaviour* rather than a name can stop matching without leaving
# any forbidden word behind — the tree still compiles, still says ZTARC
# everywhere, and quietly loses the change. So each such rule is paired below
# with an assertion that its result is actually present, in the file it was meant
# to land in. ztarc-windows shipped a release with its patches silently
# unapplied before it learned this; see its commit e13e448.
#
# Brand values are read from brand/brand.env rather than spelled here, so this
# file cannot drift from brand/rules.sed without the drift showing up as a
# failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$ROOT/build/src"

# shellcheck disable=SC1091
. "$ROOT/scripts/brand.sh"
ztarc_brand

[ -d "$DST" ] || { echo "nothing staged — run scripts/rebrand.sh" >&2; exit 1; }

fail=0
note() { echo "  ✗ $1" >&2; fail=1; }

# ── 1. Forbidden words ────────────────────────────────────────────────────────
# Two exemptions, each with its reason.
#
#   PangolinGo / libpangolin  the Swift module and static-library names for the
#                             Go core. Code, not branding: renaming them means
#                             rewriting module.modulemap, OTHER_LDFLAGS, the
#                             upstream Makefile and two imports, for something no
#                             user ever sees.
#   github.com/fosrl          the Go module path and the newt/olm dependencies.
#                             Same reason.
#   LICENSE, NOTICE           upstream's copyright notice, and our record of
#                             what we changed and what it derives from. AGPL-3
#                             *requires* both; naming the upstream project here
#                             is the compliance, and removing the name would be
#                             the violation rather than the fix.
echo "audit  forbidden words"
hits="$(grep -rIn --binary-files=without-match -iE 'pangolin|fossorial' "$DST" 2>/dev/null \
    | grep -v "^$DST/LICENSE:" \
    | grep -v "^$DST/LICENSE.txt:" \
    | grep -v "^$DST/NOTICE.txt:" \
    | grep -v 'PangolinGo' \
    | grep -v 'libpangolin' \
    | grep -v 'github\.com/fosrl')"
if [ -n "$hits" ]; then
    note "upstream name survives in the staged tree:"
    echo "$hits" | sed "s|^$DST/|      |" >&2
fi

# ── 2. Required results ───────────────────────────────────────────────────────
# <path under build/src>|<extended regex that must match>|<what breaks without it>
REQUIRED=(
"$BRAND_NAME.xcodeproj/project.pbxproj|PRODUCT_BUNDLE_IDENTIFIER = $BRAND_BUNDLE_ID;|the app would install under the upstream vendor's identifier and share their preferences, containers and login item"
"$BRAND_NAME.xcodeproj/project.pbxproj|PRODUCT_BUNDLE_IDENTIFIER = $BRAND_EXT_BUNDLE_ID;|the system extension would register under the upstream vendor's identifier"
"$BRAND_NAME.xcodeproj/project.pbxproj|path = $BRAND_EXT_BUNDLE_ID.systemextension;|PRODUCT_NAME on a system-extension target resolves to its bundle id, so the Embed System Extensions phase would look for a file the build no longer produces"
"$BRAND_NAME.xcodeproj/project.pbxproj|kind = exactVersion;|Sparkle would resolve to whatever the newest 2.x is that day, so builds would not be reproducible and an upstream release could break CI with no change here"
"$BRAND_NAME/macOS/$BRAND_NAME.entitlements|$BRAND_APP_GROUP|the app and an installed Pangolin client would share one container"
"PacketTunnel/macOS/PacketTunnel.entitlements|$BRAND_APP_GROUP|the extension and an installed Pangolin client would share one container"
"PacketTunnel/macOS/Info.plist|$BRAND_MACH_SERVICE|macOS requires NEMachServiceName to be prefixed by an app group the extension is entitled to; otherwise the extension cannot be reached, with no error that names the cause"
"$BRAND_NAME/Shared/ConfigManager.swift|defaultHostname = \"$BRAND_SERVER_URL\"|the login window would default to the upstream vendor's hosted service"
"$BRAND_NAME/Shared/TunnelManager.swift|localizedDescription = \"$BRAND_NAME\"|System Settings > VPN would list the connection under the upstream name"
"$BRAND_NAME/Shared/TunnelManager.swift|serverAddress = \"$BRAND_NAME\"|the VPN configuration would carry the upstream name"
"$BRAND_NAME/macOS/${BRAND_NAME}App.swift|startingUpdater: false|Sparkle would start and poll a feed we do not control, signed with a key we do not hold"
"$BRAND_NAME/macOS/UI/MenuBarView.swift|Source Code|the tray menu would not offer the source, which AGPL-3 obliges us to do"
"$BRAND_NAME/macOS/UI/Preferences/AboutContentView.swift|Source Code|the About tab would not offer the source, which AGPL-3 obliges us to do"
"$BRAND_NAME/Shared/ConfigManager.swift|$BRAND_CONFIG_FILE|the client would read and write the upstream client's config file"
"$BRAND_NAME.xcodeproj/project.pbxproj|ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;|the build would look for an app icon that staging deleted, and ship with none"
)

echo "audit  required results"
for entry in "${REQUIRED[@]}"; do
    IFS='|' read -r path needle why <<< "$entry"
    if [ ! -f "$DST/$path" ]; then
        note "$path is missing — expected to find /$needle/ in it; without it, $why"
    elif ! grep -qE -- "$needle" "$DST/$path"; then
        note "$path no longer matches /$needle/ — without it, $why"
        note "  update brand/rules.sed, brand/overrides/ or the patch that used to do this."
    fi
done

# ── 3. Forbidden results ──────────────────────────────────────────────────────
FORBIDDEN=(
"$BRAND_NAME.xcodeproj/project.pbxproj|$UPSTREAM_TEAM_ID|the build would be attributed to the upstream vendor's Apple Developer team"
"$BRAND_NAME.xcodeproj/project.pbxproj|CODE_SIGN_IDENTITY\\[sdk=macosx|an sdk-conditional signing identity may outrank build-app.sh's command-line override"
"$BRAND_NAME.xcodeproj/project.pbxproj|PROVISIONING_PROFILE_SPECIFIER\\[sdk=macosx|the build would require a provisioning profile that exists under no team but the upstream vendor's"
"$BRAND_NAME.xcodeproj/project.pbxproj|PangoliniOS|the iOS targets were not stripped"
"$BRAND_NAME.xcodeproj/project.pbxproj|PacketTunneliOS|the iOS targets were not stripped"
"$BRAND_NAME/macOS/UI/MenuBarView.swift|Terms of Service|ztarc.io has no such page; the entry would go nowhere"
"$BRAND_NAME/macOS/UI/LoginView.swift|Privacy Policy|the login window would ask the user to agree to a document that does not exist"
"$BRAND_NAME/macOS/UI/OnboardingFlowView.swift|Terms of Service|onboarding would record the user's agreement to a document that does not exist"
)

echo "audit  forbidden results"
for entry in "${FORBIDDEN[@]}"; do
    IFS='|' read -r path needle why <<< "$entry"
    if [ -f "$DST/$path" ] && grep -qE -- "$needle" "$DST/$path"; then
        note "$path still matches /$needle/ — $why"
    fi
done

# ── 3b. Forbidden Info.plist keys ─────────────────────────────────────────────
# Checked as parsed keys rather than as text, because brand/overrides explains in
# a comment which Sparkle keys it removes and why. A file that documents an
# absence is not the same as a file that has the key, and a grep cannot tell the
# difference.
echo "audit  forbidden plist keys"
for key in SUFeedURL SUPublicEDKey SUEnableDownloaderService SUEnableInstallerLauncherService; do
    if plutil -extract "$key" raw -o - "$DST/$BRAND_NAME/macOS/Info.plist" >/dev/null 2>&1; then
        note "$BRAND_NAME/macOS/Info.plist still declares $key — the updater would have a feed or a signing key that is not ours"
    fi
done

# ── 4. Project integrity ──────────────────────────────────────────────────────
# scripts/strip-ios.py rewrites project.pbxproj with our own OpenStep emitter.
# These checks are what make that safe without opening Xcode: the file still
# parses, every object id still resolves, and exactly the two macOS targets
# remain. CI adds `xcodebuild -list`, which is the authoritative parse.
echo "audit  project integrity"
PBX="$DST/$BRAND_NAME.xcodeproj/project.pbxproj"
if ! plutil -lint "$PBX" >/dev/null 2>&1; then
    note "$BRAND_NAME.xcodeproj/project.pbxproj does not parse as a property list"
else
    python3 - "$PBX" <<'PY' || fail=1
import plistlib, re, subprocess, sys
path = sys.argv[1]
d = plistlib.loads(subprocess.run(
    ["plutil", "-convert", "xml1", "-o", "-", path],
    capture_output=True, check=True).stdout)
objects, root_id = d["objects"], d["rootObject"]
root = objects[root_id]
ok = True

names = sorted(o["name"] for o in objects.values()
               if o.get("isa") == "PBXNativeTarget")
if names != ["PacketTunnel", "ZTARC"]:
    print("  ✗ expected exactly the two macOS targets, found %s" % names,
          file=sys.stderr)
    ok = False

dangling = sorted({m for m in re.findall(r"\b[0-9A-F]{24}\b", open(path).read())
                   if m not in objects and m != root_id})
if dangling:
    print("  ✗ project references object ids that do not exist: %s" % dangling,
          file=sys.stderr)
    ok = False

attrs = set(root.get("attributes", {}).get("TargetAttributes", {}))
if not attrs <= set(objects):
    print("  ✗ TargetAttributes names targets that were removed: %s"
          % sorted(attrs - set(objects)), file=sys.stderr)
    ok = False

for o in objects.values():
    if o.get("isa") == "XCBuildConfiguration":
        sdk = o.get("buildSettings", {}).get("SDKROOT", "")
        if sdk in ("iphoneos", "iphonesimulator"):
            print("  ✗ an iOS build configuration survived the strip",
                  file=sys.stderr)
            ok = False

sys.exit(0 if ok else 1)
PY
fi

# Artwork the forbidden-word scan is blind to. Every check above reads text; an
# image is bytes, and an asset catalog that still held the upstream mark would
# pass all of them while the product wore someone else's face in the Dock.
for asset in "AppIcon.appiconset/icon_512x512@2x.png" "MenuBarIcon.imageset/menubar-icon@2x.png" \
             "AccentColor.colorset/Contents.json" "${BRAND_NAME}Logo.imageset/Contents.json"; do
    [ -f "$DST/$BRAND_NAME/Assets.xcassets/$asset" ] || \
        note "Assets.xcassets/$asset is missing — run scripts/make-icons.sh"
done
[ -e "$DST/$BRAND_NAME/pangolin-app-icon.icon" ] && \
    note "upstream's Icon Composer bundle survived staging; it holds their mark as vector art"
if ! grep -qE '"red"[[:space:]]*:[[:space:]]*"0\.913' "$DST/$BRAND_NAME/Assets.xcassets/AccentColor.colorset/Contents.json" 2>/dev/null; then
    note "the accent colour is not the ZTARC ember (#E95C2C); the asset overlay did not land"
fi

for d in "$BRAND_NAME/iOS" "PacketTunnel/iOS"; do
    [ -e "$DST/$d" ] && note "$d still exists; the iOS sources were not removed"
done
if ls "$DST/$BRAND_NAME.xcodeproj/xcshareddata/xcschemes/" 2>/dev/null | grep -qi ios; then
    note "an iOS scheme survived; xcodebuild -list would advertise a scheme nobody can build"
fi

if [ "$fail" -ne 0 ]; then
    echo "brand audit FAILED" >&2
    exit 1
fi
echo "brand audit clean"
