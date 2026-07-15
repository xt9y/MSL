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

GUEST_SRC = Guest/msld.c

all: sign $(BUILD_DIR)/msld

$(PRODUCT): $(SWIFT_SRCS) $(OBJC_SRCS)
	@mkdir -p $(BUILD_DIR)
	$(SWIFTC) $(SWIFT_FLAGS) \
		-import-objc-header $(OBJC_HEADER) \
		-o $@ \
		$(SWIFT_SRCS) $(OBJC_SRCS)
	@echo "Build complete: $(PRODUCT)"

$(BUILD_DIR)/msld: $(GUEST_SRC)
	@mkdir -p $(BUILD_DIR)
	aarch64-linux-musl-gcc -static -Os -s -o $@ $^

sign: $(PRODUCT)
	codesign --entitlements Resources/msl.entitlements \
		--force \
		--sign - \
		$(PRODUCT)
	@echo "Signed: $(PRODUCT)"

clean:
	rm -rf $(BUILD_DIR)

release: sign
	git add -A
	git commit -q -m "Release v$(VERSION)" 2>/dev/null || true
	git push origin main
	git tag -f v$(VERSION)
	git push origin v$(VERSION) -f
	@echo "Released v$(VERSION)"

homebrew-upload: release
	[ -n "$$GH_TOKEN" ] || { echo "Error: GH_TOKEN not set. Add to ~/.zshrc or run: export GH_TOKEN=your_token"; exit 1; }; \
	rm -rf /tmp/homebrew-msl; \
	git clone https://felixjaschul:$$GH_TOKEN@github.com/xt9y/homebrew-msl.git /tmp/homebrew-msl; \
	git archive --format=tar.gz -o /tmp/msl-$(VERSION).tar.gz --prefix=msl-$(VERSION)/ v$(VERSION); \
	SHA=$$(shasum -a 256 /tmp/msl-$(VERSION).tar.gz | cut -d' ' -f1); \
	sed -i '' "s|url \".*\"|url \"https://github.com/xt9y/msl/archive/refs/tags/v$(VERSION).tar.gz\"|" /tmp/homebrew-msl/Formula/msl.rb; \
	sed -i '' "s|sha256 \".*\"|sha256 \"$$SHA\"|" /tmp/homebrew-msl/Formula/msl.rb; \
	cd /tmp/homebrew-msl && git add Formula/msl.rb && git commit -m "Update msl to v$(VERSION)" && git push; \
	rm -f /tmp/msl-$(VERSION).tar.gz; \
	echo "Homebrew tap updated to v$(VERSION)"

.PHONY: all sign clean
