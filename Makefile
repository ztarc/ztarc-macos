# Build the ZTARC macOS client from the pinned upstream submodule.
#
# upstream/ is read, never written. Branding is applied to a staged copy under
# build/src by scripts/rebrand.sh, and scripts/audit-brand.sh refuses to build
# anything that still calls itself by the upstream name.
#
# Every target here is a thin call into scripts/, because the CI job runs the
# same scripts. Two copies of the build would drift; one cannot.
#
# Unlike the Windows client, none of this cross-compiles: xcodebuild, codesign,
# lipo and iconutil are macOS-only, and full Xcode 26+ is required — Command
# Line Tools are not enough.

BUILD := build

.PHONY: all build stage dmg app clean version upstream-version icons check

all: build

build: app dmg

stage:
	@./scripts/rebrand.sh
	@./scripts/audit-brand.sh

app: stage
	@./scripts/build-app.sh

dmg: app
	@./scripts/build-dmg.sh

# Stage and audit without building. The whole rebrand is checkable this way on a
# machine with no Xcode and no Go, which is most of what changes here.
check: stage

# Regenerate brand/assets from the logo in ztarc-website. Committed output, so
# this is only needed when the logo itself changes.
icons:
	@./scripts/make-icons.sh

version:
	@. ./scripts/version.sh && ztarc_version

# Which upstream commit this tree is pinned to. Must agree with UPSTREAM in
# brand/version.env.
upstream-version:
	@git -C upstream describe --tags --always

clean:
	@rm -rf $(BUILD)
