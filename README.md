# ZTARC for macOS

The ZTARC macOS client, built from the Pangolin Apple client without forking it.

[fosrl/apple](https://github.com/fosrl/apple) is pinned as a submodule under
`upstream/` and is **read, never written**. Branding is applied to a disposable
copy under `build/src`, and `scripts/audit-brand.sh` refuses to build anything
that still calls itself by the upstream name.

That constraint is the whole design. Because we never edit `upstream/`,
`git -C upstream status` stays clean and moving to a new upstream release is a
checkout rather than a merge against our own changes.

```
upstream/ ──stage──▶ build/src ──▶ audit ──▶ make ──▶ xcodebuild ──▶ hdiutil
            patches → strip-ios → sed → renames → overrides → assets
```

## Build

```sh
git submodule update --init
make build              # → build/ZTARC.app and build/ztarc-0.11.1.1.dmg
make check              # stage and audit only — no Xcode or Go needed
make version            # 0.11.1.1
make upstream-version   # mac-0.11.1
make icons              # regenerate brand/assets (rarely needed)
make clean
```

Needs **Xcode 26** (the project is `objectVersion = 77`) and the Go version in
`upstream/PangolinGo/.go-version`. Command Line Tools alone are not enough;
`xcodebuild` will say so. `make check` deliberately needs neither, because most
changes here are to the rebranding rather than to the app.

The first build rsyncs and patches a private copy of GOROOT into `.cache/go`,
which takes a while and is then reused.

## What works, and what does not

**This build is not signed.** It is ad-hoc signed, because an arm64 binary with
no signature at all will not execute — but it carries no Developer ID.

That means **the tunnel does not work**. macOS validates the restricted
`com.apple.developer.*` entitlements against a provisioning profile or the
signing certificate, and ad-hoc has neither, so `OSSystemExtensionManager`
refuses to activate the packet tunnel and no VPN configuration can be created.
The app launches, the menu bar item appears, onboarding and preferences render,
and every branded surface is real. Connecting is not yet possible.

This is the one place the Windows client's "defer signing" posture does not
transfer: Gatekeeper is considerably less forgiving than SmartScreen. Treat this
pass as proof of the rebrand, not of the product.

Two consequences worth knowing so nobody chases them as bugs:

- Gatekeeper blocks a first double click on the downloaded app. Right-click →
  Open, or `xattr -dr com.apple.quarantine /Applications/ZTARC.app`.
- An ad-hoc signed app's keychain identity is derived from its code hash, which
  changes on every build, so saved credentials do not survive a rebuild. Expect
  to log in again each time.

Unblocking all of it needs, in order: an Apple Developer Program membership; an
approved Network Extension entitlement request; a registered
`group.io.ztarc.ZTARC` app group; a Developer ID Application certificate; and
ZTARC provisioning profiles. `scripts/build-app.sh` already reads the identity,
team and profile from the environment, so switching over is setting variables,
not restructuring.

## How the rebranding works

Four layers, ordered most to least tolerant of upstream drift. **Use the least
fragile layer that can express the change.**

| Layer | Where | For |
|---|---|---|
| `brand/patches/*.patch` | applied first, against pristine upstream | structural edits — removing a SwiftUI section, deleting a view |
| `brand/rules.sed` | every text file in the staging tree | names, URLs, identifiers, log subsystems |
| `brand/overrides/` | whole files | `Info.plist`, entitlements — anything where what matters is what is *absent* |
| `brand/assets/` | artwork | app icon, menu bar icons, logo, accent colour |

Plus `scripts/strip-ios.py`, which removes the two iOS targets from the Xcode
project structurally rather than as a patch, because a diff against a 1145-line
generated `project.pbxproj` would conflict on every upstream bump. It walks the
object graph and keeps what is reachable, so it stays correct when upstream
rearranges things. It writes the file back in OpenStep format — the format Xcode
itself writes — so there is never a question of whether the result is accepted.

`brand/brand.env` holds the names. `brand/rules.sed` spells them out literally so
the rules stay greppable; `scripts/audit-brand.sh` reads `brand.env` and asserts
the results, so the two cannot silently disagree.

### The audit is the point

**`scripts/audit-brand.sh` is what makes this safe.** A sed rule that stops
matching after an upstream bump fails silently: nothing errors, and a
ZTARC-named binary greets people under someone else's name.

Absence of the upstream name proves nothing on its own either. A substitution
that targets a *behaviour* rather than a name can stop matching without leaving
any forbidden word behind — the tree still compiles, still says ZTARC
everywhere, and quietly loses the change. So every such rule is paired with an
assertion that its result is present, in the file it was meant to land in.

**If you add a behavioural change, add its assertion in the same commit.**
ztarc-windows shipped a release with its patches silently unapplied before it
learned this; see its commit `e13e448`.

The forbidden-word scan has exactly three exemptions, each with its reason
written beside it in the script:

- `PangolinGo` / `libpangolin` — the Swift module and static library names for
  the Go core. Renaming them means rewriting `module.modulemap`, `OTHER_LDFLAGS`,
  upstream's `Makefile` and two `import` statements, for something no user sees.
- `github.com/fosrl/...` — the Go module path and the `newt` / `olm`
  dependencies. Dependencies, not branding.
- `LICENSE` and `NOTICE` — AGPL-3 *requires* retaining upstream's attribution.
  Naming the upstream project there is the compliance; removing it would be the
  violation.

The audit also checks the artwork exists and the accent colour is ours, because
every other check reads text and an image is bytes.

## What changed, and what deliberately did not

| | Upstream | ZTARC |
|---|---|---|
| App | `Pangolin.app` | `ZTARC.app` |
| Bundle ID | `net.pangolin.Pangolin` | `io.ztarc.ZTARC` |
| Extension | `…Pangolin.PacketTunnel` | `io.ztarc.ZTARC.PacketTunnel` |
| App group | `group.net.pangolin.Pangolin` | `group.io.ztarc.ZTARC` |
| URL scheme | `pangolin://` | `ztarc://` |
| VPN profile name | `Pangolin` | `ZTARC` |
| Support dir | `~/Library/Application Support/Pangolin` | `…/ZTARC` |
| Config | `pangolin.json` | `ztarc.json` |
| Default server | `app.pangolin.net` | `console.ztarc.io` |
| Links | docs / terms / privacy | source code only |
| Auto-update | Sparkle, upstream's feed and key | disabled |
| Platforms | macOS + iOS | macOS |

The bundle identifier, app group and VPN profile name are **not cosmetic**.
Sharing them with an installed Pangolin client would put two products in one
container and one VPN configuration — the macOS analogue of the named-pipe
collision the Windows client's README warns about.

Deliberately unchanged: `PangolinGo`, `libpangolin`, `module.modulemap` and
`github.com/fosrl/newt` + `.../olm`. Internal names and dependencies, invisible
to users, and renaming them would be a large diff against a moving upstream for
no benefit.

## Rebasing on a new upstream

```sh
git -C upstream fetch --tags && git -C upstream checkout mac-<x.y.z>
# set UPSTREAM in brand/version.env, reset BUILD to 1
make check            # the patches and the audit will say what drifted
git add upstream brand/version.env && git commit
```

If a patch no longer applies, re-author it against the new upstream rather than
forcing it. If an assertion fails, the message names the file, what it was
looking for, and what breaks without it.

## Releasing

```sh
make version          # brand/version.env is the source of truth
git tag v0.11.1.1
git push --tags
```

CI refuses a tag that disagrees with `brand/version.env`, and refuses a build
whose submodule pin disagrees with the `UPSTREAM` it claims. A release whose
page, filename and `Info.plist` state three different numbers is worse than no
release; to publish a fix on the same upstream base, bump `BUILD` first.

## Known gaps

- **Not signed or notarized.** See above. This is the one that matters.
- **The wordmark is 240×60.** `brand/assets` generates the logo imageset from
  the same artwork the Windows client ships, which has no larger version. It
  will be soft on a Retina display. Regenerate from vector art when there is
  some — `scripts/make-icons.sh` is where.
- **The app icon is upscaled** from a 256×256 master for the same reason.
- **Two onboarding screenshots were removed** rather than replaced. They showed
  macOS dialogs with the upstream product's name rendered as pixels, which no
  substitution can reach and no text audit can see. Their instructions remain.
  Re-shooting them needs a signed build, because the dialogs only appear when
  the system extension actually loads.

## Licence

AGPL-3. This is a modified version of the Pangolin client for Apple devices,
Copyright (c) 2025 Fossorial, Inc. See `LICENSE` for the terms and `NOTICE` for
what was changed.
