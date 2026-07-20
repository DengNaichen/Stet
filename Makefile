PUBLIC_STET_DIR := Public/Stet
PRIVATE_STET_MOBILE_DIR := Private/StetMobile
IOS_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
IOS_XCODEBUILD := $(IOS_DEVELOPER_DIR)/usr/bin/xcodebuild

PUBLIC_SWIFT_DIRS := $(PUBLIC_STET_DIR)/StetMac $(PUBLIC_STET_DIR)/StetMacTests $(PUBLIC_STET_DIR)/StetMacUITests $(PUBLIC_STET_DIR)/StetVisuals
PRIVATE_SWIFT_DIRS := $(PRIVATE_STET_MOBILE_DIR)/StetKeyboard $(PRIVATE_STET_MOBILE_DIR)/StetLiveActivity $(PRIVATE_STET_MOBILE_DIR)/StetMobile $(PRIVATE_STET_MOBILE_DIR)/StetMobileTests $(PRIVATE_STET_MOBILE_DIR)/StetMobileUITests

.PHONY: help verify-public public-export swiftlint format format-lint lint whisper-deps build ci-build test ios-bootstrap ios-build doctor clean-derived-data release-github notary-setup

help:
	@echo "Available targets:"
	@echo "  swiftlint       Run SwiftLint"
	@echo "  format          Format Swift sources with swift-format"
	@echo "  format-lint     Lint Swift formatting with swift-format"
	@echo "  lint            Run SwiftLint and swift-format lint"
	@echo "  build           Build the macOS app"
	@echo "  ci-build        Build without code signing for CI"
	@echo "  test            Run StetTests on macOS"
	@echo "  ios-bootstrap   Download the ignored iOS runtime frameworks"
	@echo "  ios-build       Build the private iOS app for the simulator"
	@echo "  verify-public   Verify the public projection boundary"
	@echo "  public-export   Print the commit that can be pushed to the public repo"
	@echo "  doctor          Report Xcode and project build-cache usage"
	@echo "  clean-derived-data  Remove only Stet/StetMobile build caches"
	@echo "  release-github  Build signed GitHub release artifacts"
	# @echo "  publish-github  Publish GitHub release artifacts"
	@echo "  notary-setup    Configure notarytool profile"

verify-public:
	./scripts/verify-public-boundary.sh

public-export: verify-public
	./scripts/publish-public.sh

swiftlint:
	swiftlint lint --config .swiftlint.yml --strict --no-cache

format:
	xcrun swift-format format --in-place --recursive --parallel --configuration .swift-format $(PUBLIC_SWIFT_DIRS) $(PRIVATE_SWIFT_DIRS)

format-lint:
	xcrun swift-format lint --strict --recursive --parallel --configuration .swift-format $(PUBLIC_SWIFT_DIRS) $(PRIVATE_SWIFT_DIRS)

lint: swiftlint format-lint

whisper-deps:
	@echo "whisper is resolved through Swift Package Manager; no local dependency preparation is required."

build:
	$(MAKE) -C $(PUBLIC_STET_DIR) build

ci-build:
	$(MAKE) -C $(PUBLIC_STET_DIR) ci-build

test:
	$(MAKE) -C $(PUBLIC_STET_DIR) test

ios-bootstrap:
	$(PRIVATE_STET_MOBILE_DIR)/scripts/bootstrap-sherpa-runtime.sh

ios-build: ios-bootstrap
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) $(IOS_XCODEBUILD) -project $(PRIVATE_STET_MOBILE_DIR)/StetMobile.xcodeproj -scheme StetMobile -sdk iphonesimulator27.0 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

doctor:
	$(MAKE) -C $(PUBLIC_STET_DIR) doctor

clean-derived-data:
	$(MAKE) -C $(PUBLIC_STET_DIR) clean-derived-data

release-github:
	$(MAKE) -C $(PUBLIC_STET_DIR) release-github

# publish-github:
# 	./scripts/publish-github-release.sh

notary-setup:
	$(MAKE) -C $(PUBLIC_STET_DIR) notary-setup
