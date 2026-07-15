SWIFTC = xcrun swiftc
SWIFT_FLAGS = -framework Virtualization -O -Xcc -fobjc-arc
BUILD_DIR = build
PRODUCT = $(BUILD_DIR)/msl

SWIFT_SRCS = \
	Sources/main.swift \
	Sources/Daemon.swift \
	Sources/VM.swift \
	Sources/IPC.swift \
	Sources/State.swift \
	Sources/Setup.swift

OBJC_SRCS = Sources/MSLVSOCK.m
OBJC_HEADER = Sources/BridgingHeader.h

all: sign

$(PRODUCT): $(SWIFT_SRCS) $(OBJC_SRCS)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		-import-objc-header $(OBJC_HEADER) \
		-o $@ \
		$(SWIFT_SRCS) $(OBJC_SRCS)
	@echo "Build complete: $(PRODUCT)"

sign: $(PRODUCT)
	codesign --entitlements Resources/msl.entitlements \
		--force \
		--sign - \
		$(PRODUCT)
	@echo "Signed: $(PRODUCT)"

clean:
	rm -rf $(BUILD_DIR)

# ─────────────────────────────────────────────────────────────────────
# Release: commit, tag, push msl repo, then update & push homebrew tap.
#
# Usage:
#   make release MSG="v1.1.0: production hardening"
#
# What it does:
#   1. Reads the version from Sources/Setup.swift (MSLVersion)
#   2. Fails if MSLVersion doesn't match the latest git tag (version drift)
#   3. Commits all staged changes with MSG
#   4. Pushes to origin and tags v<version>
#   5. Downloads the new GitHub tarball and computes sha256
#   6. Clones/pulls homebrew-msl tap at /tmp/homebrew-msl
#   7. Updates url + sha256 in Formula/msl.rb and Formula/msld.rb
#   8. Commits and pushes the tap
#
# Prerequisites:
#   - Bump MSLVersion in Sources/Setup.swift BEFORE running
#
# Notes:
# - Code signing uses ad-hoc identity (--sign -) because msl doesn't have
#   a paid Apple Developer ID. Users may see a Gatekeeper warning on first
#   run. To fix permanently: obtain a Developer ID, replace --sign - with
#   --sign "Developer ID Application: ...", and notarize the binary.
# ─────────────────────────────────────────────────────────────────────
release: verify-version
	@VER=$$(grep -o 'MSLVersion = "[^"]*"' Sources/Setup.swift | grep -o '[0-9]*\.[0-9]*\.[0-9]*'); \
	echo "Releasing v$$VER ..."; \
	git add -A; \
	git commit -m "$(MSG)"; \
	git push; \
	git tag "v$$VER"; \
	git push origin "v$$VER"; \
	echo "Tagged v$$VER, downloading tarball..."; \
	SHA=$$(curl -sL "https://github.com/xt9y/msl/archive/refs/tags/v$$VER.tar.gz" | shasum -a 256 | awk '{print $$1}'); \
	echo "sha256: $$SHA"; \
	if [ -d /tmp/homebrew-msl ]; then \
		cd /tmp/homebrew-msl && git pull; \
	else \
		git clone https://github.com/xt9y/homebrew-msl.git /tmp/homebrew-msl; \
	fi; \
	sed -i '' "s|url \".*\"|url \"https://github.com/xt9y/msl/archive/refs/tags/v$$VER.tar.gz\"|" /tmp/homebrew-msl/Formula/msl.rb /tmp/homebrew-msl/Formula/msld.rb; \
	sed -i '' "s|sha256 \".*\"|sha256 \"$$SHA\"|" /tmp/homebrew-msl/Formula/msl.rb /tmp/homebrew-msl/Formula/msld.rb; \
	cd /tmp/homebrew-msl && git add Formula/msl.rb Formula/msld.rb && \
	git commit -m "$(MSG)" && git push; \
	echo "Done: v$$VER published to homebrew."

# Verify MSLVersion in Setup.swift matches the latest git tag.
# Prevents version drift where --version lies about the actual release.
verify-version:
	@VER=$$(grep -o 'MSLVersion = "[^"]*"' Sources/Setup.swift | grep -o '[0-9]*\.[0-9]*\.[0-9]*'); \
	LATEST_TAG=$$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); \
	if [ -n "$$LATEST_TAG" ] && [ "$$VER" = "$$LATEST_TAG" ]; then \
		echo "ERROR: MSLVersion ($$VER) matches latest tag ($$LATEST_TAG). Bump it first!"; \
		exit 1; \
	fi; \
	echo "Version OK: $$VER (latest tag: $$LATEST_TAG)"

.PHONY: all sign clean release verify-version
