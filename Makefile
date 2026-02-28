# Understory — Makefile
# Builds a universal .app bundle (arm64 + x86_64) with icons and privacy manifest.

APP_NAME     = Understory
APP_BUNDLE   = $(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
APP_MACOS    = $(APP_CONTENTS)/MacOS
APP_RESOURCES= $(APP_CONTENTS)/Resources

RES_DIR      = Sources/Understory/Resources
ENTITLEMENTS = Understory.entitlements

# Architecture-specific build directories
BUILD_ARM    = .build/arm64-apple-macosx/release
BUILD_X86    = .build/x86_64-apple-macosx/release

.PHONY: all build bundle run clean

all: bundle

build:
	@echo "🔨 Compiling Swift sources (universal: arm64 + x86_64)..."
	swift build -c release --arch arm64
	@echo "  ✓ arm64 built"
	swift build -c release --arch x86_64
	@echo "  ✓ x86_64 built"
	@echo "🔗 Creating universal binary via lipo..."
	@mkdir -p .build/universal
	lipo -create \
		$(BUILD_ARM)/$(APP_NAME) \
		$(BUILD_X86)/$(APP_NAME) \
		-output .build/universal/$(APP_NAME)
	@echo "  ✓ Universal binary created"
	@# Verify architectures
	@lipo -info .build/universal/$(APP_NAME)

bundle: build
	@echo "📦 Assembling .app bundle..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_MACOS) $(APP_RESOURCES)
	@# Universal binary
	@cp .build/universal/$(APP_NAME) $(APP_MACOS)/$(APP_NAME)
	@# Info.plist
	@cp Info.plist $(APP_CONTENTS)/Info.plist
	@# App Icon
	@if [ -f "$(RES_DIR)/AppIcon.icns" ]; then \
		cp "$(RES_DIR)/AppIcon.icns" "$(APP_RESOURCES)/AppIcon.icns"; \
		echo "  ✓ App icon installed"; \
	fi
	@# Menu Bar Icon
	@for f in MenuIcon.png MenuIcon@2x.png; do \
		if [ -f "$(RES_DIR)/$$f" ]; then cp "$(RES_DIR)/$$f" "$(APP_RESOURCES)/$$f"; fi; \
	done
	@echo "  ✓ Menu bar icon installed"
	@# Privacy Manifest
	@if [ -f "PrivacyInfo.xcprivacy" ]; then \
		cp PrivacyInfo.xcprivacy "$(APP_RESOURCES)/PrivacyInfo.xcprivacy"; \
		echo "  ✓ Privacy manifest installed"; \
	fi

	@# SPM resource bundle
	@if [ -d "$(BUILD_ARM)/Understory_Understory.bundle" ]; then \
		cp -R "$(BUILD_ARM)/Understory_Understory.bundle" "$(APP_RESOURCES)/"; \
	fi
	@# Ad-hoc code sign for local development
	@codesign --force --sign - $(APP_BUNDLE) 2>/dev/null && \
		echo "  ✓ Ad-hoc code signed" || \
		echo "  ⚠ Code signing skipped (no identity)"
	@echo "✅ $(APP_BUNDLE) ready (universal binary)."

run: bundle
	@echo "🚀 Launching $(APP_BUNDLE)..."
	@open $(APP_BUNDLE)

# Sign for App Store distribution (requires Apple Developer identity)
# Usage: make sign IDENTITY="3rd Party Mac Developer Application: Your Name (TEAMID)"
sign: bundle
	@echo "🔏 Signing for distribution with sandbox..."
	codesign --force --sign "$(IDENTITY)" --entitlements $(ENTITLEMENTS) --options runtime $(APP_BUNDLE)
	@echo "✅ Signed with: $(IDENTITY)"

clean:
	@rm -rf .build $(APP_BUNDLE)
	@echo "🧹 Cleaned."
