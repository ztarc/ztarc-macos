#!/usr/bin/env bash
# The version, read out of the one file that declares it.
#
# Sourced rather than executed, so the staged Info.plist, the .app's own
# properties, the DMG filename and the release tag cannot drift apart.

ztarc_version() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck disable=SC1091
    . "$root/brand/version.env"
    [ -n "${UPSTREAM:-}" ] && [ -n "${BUILD:-}" ] || {
        echo "cannot read version from brand/version.env" >&2
        return 1
    }
    echo "$UPSTREAM.$BUILD"
}

# The upstream tag half on its own, for the check that it agrees with the
# submodule pin.
ztarc_upstream_version() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    # shellcheck disable=SC1091
    . "$root/brand/version.env"
    echo "$UPSTREAM"
}
