#!/usr/bin/env bash
# The brand constants, loaded from the one file that declares them.
#
# Sourced by rebrand.sh, audit-brand.sh, build-app.sh and build-dmg.sh so that a
# rename happens in brand/brand.env and nowhere else. Every variable is exported,
# because scripts/rebrand.sh expands them into the generated sed rules.

ztarc_brand() {
    local root
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    set -a
    # shellcheck disable=SC1091
    . "$root/brand/brand.env"
    set +a
    [ -n "${BRAND_NAME:-}" ] && [ -n "${BRAND_BUNDLE_ID:-}" ] || {
        echo "cannot read brand from brand/brand.env" >&2
        return 1
    }
}
