.PHONY: help swiftlint format format-lint lint build ci-build test release-github notary-setup

help:
	@echo "Available targets:"
	@echo "  swiftlint       Run SwiftLint"
	@echo "  format          Format Swift sources with swift-format"
	@echo "  format-lint     Lint Swift formatting with swift-format"
	@echo "  lint            Run SwiftLint and swift-format lint"
	@echo "  build           Build the macOS app"
	@echo "  ci-build        Build without code signing for CI"
	@echo "  test            Run StetTests on macOS"
	@echo "  release-github  Build signed GitHub release artifacts"
	# @echo "  publish-github  Publish GitHub release artifacts"
	@echo "  notary-setup    Configure notarytool profile"

swiftlint:
	swiftlint lint --config .swiftlint.yml --strict --no-cache

format:
	xcrun swift-format format --in-place --recursive --parallel --configuration .swift-format Stet StetTests StetUITests StetVisuals

format-lint:
	xcrun swift-format lint --strict --recursive --parallel --configuration .swift-format Stet StetTests StetUITests StetVisuals

lint: swiftlint format-lint

# Dependency Management
DEPS_DIR := $(CURDIR)/.deps
WHISPER_REPO := https://github.com/ggerganov/whisper.cpp.git
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
WHISPER_XCFRAMEWORK := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework

# Helper to find the actual framework path within XCFramework for macOS
# This handles different architecture folder names like macos-arm64_x86_64
MACOS_FRAMEWORK_DIR = $(shell find $(WHISPER_XCFRAMEWORK) -name "macos-*" -type d | head -1)

.PHONY: whisper-deps
whisper-deps:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(WHISPER_XCFRAMEWORK)" ]; then \
		echo "Preparing whisper.xcframework..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone $(WHISPER_REPO) $(WHISPER_CPP_DIR); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already exists at $(WHISPER_XCFRAMEWORK)"; \
	fi

BUILD_FLAGS := -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' \
               FRAMEWORK_SEARCH_PATHS="$(MACOS_FRAMEWORK_DIR)" \
               OTHER_LDFLAGS="-framework whisper" \
               OTHER_SWIFT_FLAGS="-F $(MACOS_FRAMEWORK_DIR)"

# Helper to embed the framework into the built app bundle
define embed_framework
	@APP_PATH=$$(find $(HOME)/Library/Developer/Xcode/DerivedData -name "Stet Debug.app" -type d -newer Stet.xcodeproj | head -1); \
	FRAMEWORK_SOURCE=$$(find $(WHISPER_XCFRAMEWORK) -name "whisper.framework" -type d | head -1); \
	if [ -n "$$APP_PATH" ] && [ -n "$$FRAMEWORK_SOURCE" ]; then \
		echo "Embedding whisper.framework from $$FRAMEWORK_SOURCE into $$APP_PATH..."; \
		mkdir -p "$$APP_PATH/Contents/Frameworks"; \
		cp -R "$$FRAMEWORK_SOURCE" "$$APP_PATH/Contents/Frameworks/"; \
		install_name_tool -add_rpath "@executable_path/../Frameworks" "$$APP_PATH/Contents/MacOS/Stet Debug" 2>/dev/null || true; \
		echo "Embedding complete."; \
	else \
		echo "Warning: Could not find build artifact or whisper.framework to embed."; \
	fi
endef

build: whisper-deps
	xcodebuild $(BUILD_FLAGS) build
	$(call embed_framework)

ci-build: whisper-deps
	xcodebuild $(BUILD_FLAGS) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
	$(call embed_framework)

test:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:StetTests test

release-github:
	./scripts/release-macos-github.sh

# publish-github:
# 	./scripts/publish-github-release.sh

notary-setup:
	./scripts/setup-notarytool-profile.sh
