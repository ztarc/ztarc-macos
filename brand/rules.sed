# Turn upstream's Pangolin strings into ZTARC ones.
#
# Applied to the staging tree by scripts/rebrand.sh, then checked by
# scripts/audit-brand.sh — anything these rules miss fails the build rather than
# shipping. Values are spelled literally here rather than templated out of
# brand/brand.env, because a rule file you can read and grep is worth more than
# one less place to change a name; audit-brand.sh reads brand/brand.env and
# asserts the results, so the two cannot silently disagree.
#
# Order matters throughout. The URL rules must run before the general name rule,
# or "pangolin.net" becomes "ZTARC.net".

# ── Protected tokens ──────────────────────────────────────────────────────────
# PangolinGo is the Swift module name for the Go static library, libpangolin is
# that library's filename, and github.com/fosrl is the module path plus the
# newt/olm dependencies. All three are code, not branding: renaming them would
# mean rewriting module.modulemap, OTHER_LDFLAGS, the upstream Makefile and two
# import statements, for something no user ever sees. They are stashed out of
# reach here and restored at the bottom.
#
# Windows solved the same problem with `/github\.com\/fosrl/!` address guards.
# That does not work here — these tokens appear mid-line, beside strings that do
# need rewriting.
s|PangolinGo|@@ZTARC_GOMODULE@@|g
s|libpangolin|@@ZTARC_GOLIB@@|g
s|github\.com/fosrl|@@ZTARC_FOSRL@@|g

# ── URLs ──────────────────────────────────────────────────────────────────────
# ZTARC has no hosted service, so the cloud endpoint becomes the console. The
# documentation, terms and privacy pages do not exist yet; documentation points
# at the marketing site until it does, and the links that would have 404'd are
# removed outright by brand/patches/.
s|https://app\.pangolin\.net|https://console.ztarc.io|g
s|https://docs\.pangolin\.net[^"'`)]*|https://ztarc.io|g
s|https://pangolin\.net/[a-z]*|https://ztarc.io|g
s|https://pangolin\.net|https://ztarc.io|g
# Shown as bare text beside the cloud button, not as a link.
s|app\.pangolin\.net|console.ztarc.io|g

# ── Bundle identifiers ────────────────────────────────────────────────────────
# The app group must be rewritten before the bundle id it contains, or the
# longer string never matches. These are not cosmetic: the app group is the
# container the app and the system extension share, and the mach service name
# must stay prefixed by it or the extension cannot be reached — with no error
# that names the cause.
s|group\.net\.pangolin\.Pangolin|group.io.ztarc.ZTARC|g
s|net\.pangolin\.Pangolin|io.ztarc.ZTARC|g
# One dispatch queue uses a different reverse-DNS prefix than everything else.
s|com\.pangolin\.|io.ztarc.|g

# ── Identifiers that are not prose ────────────────────────────────────────────
s|"pangolin\.json"|"ztarc.json"|g
s|pangolin\.json|ztarc.json|g
# The app icon. Upstream ships an Icon Composer bundle (.icon), which only Xcode
# 26 can compile; brand/assets replaces it with a classic .appiconset, so this
# points the build at that. Dropping the .icon also drops the hard Xcode 26 floor
# to Xcode 16, for artwork we had to replace anyway — this is the one asset that
# categorically cannot keep upstream's, since it is the product's face.
s|ASSETCATALOG_COMPILER_APPICON_NAME = "pangolin-app-icon"|ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon|g
s|pangolin_orange|ztarc_orange|g
s|pangolin-logo|ztarc-logo|g
# The auth callback URL scheme. Sharing it with an installed Pangolin client
# would let either app claim the other's sign-in redirect.
s|"pangolin"|"ztarc"|g
# The user agent the client reports to the server.
s|"pangolin-\\(|"ztarc-\\(|g

# ── Auto-update ───────────────────────────────────────────────────────────────
# Sparkle points at a feed we do not control, signed with a key we do not hold —
# leaving it live would let the upstream vendor ship updates into ZTARC installs.
# Stopping the updater is one word, and it is reversible in one word: see
# brand/overrides/ZTARC/macOS/Info.plist for the other half (the feed URL and
# public key are removed there) and the README for how to turn it back on.
# scripts/audit-brand.sh asserts this rule still matches.
s|startingUpdater: true|startingUpdater: false|g

# ── Signing ───────────────────────────────────────────────────────────────────
# Upstream pins Manual signing to their Developer ID and two provisioning
# profiles that exist under no team but theirs, as sdk-conditional keys that an
# unconditional command-line override may or may not outrank. Delete them: then
# scripts/build-app.sh's overrides are the only signing settings in play, under
# either precedence rule, and the audit can prove the team id is gone.
/"CODE_SIGN_IDENTITY\[sdk=macosx\*\]"/d
/"DEVELOPMENT_TEAM\[sdk=macosx\*\]"/d
/"PROVISIONING_PROFILE_SPECIFIER\[sdk=macosx\*\]"/d
s|DEVELOPMENT_TEAM = 4668XHFAHF;|DEVELOPMENT_TEAM = "";|g

# ── Reproducibility ───────────────────────────────────────────────────────────
# Upstream asks SPM for "Sparkle, up to next major", and gitignores
# Package.resolved — so every build resolves to whatever the newest 2.x is that
# day, and an upstream Sparkle release can break CI with no change on our side.
# Pin it.
s|kind = upToNextMajorVersion;|kind = exactVersion;|g
s|minimumVersion = 2\.8\.1;|version = 2.8.1;|g

# ── Ownership ─────────────────────────────────────────────────────────────────
s|Fossorial, Inc\.|ZTARC|g
s|Fossorial|ZTARC|g

# ── The name itself ───────────────────────────────────────────────────────────
s|Pangolin|ZTARC|g
s|pangolin|ztarc|g

# ── Restore the protected tokens ──────────────────────────────────────────────
s|@@ZTARC_GOMODULE@@|PangolinGo|g
s|@@ZTARC_GOLIB@@|libpangolin|g
s|@@ZTARC_FOSRL@@|github.com/fosrl|g
