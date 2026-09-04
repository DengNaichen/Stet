IOS_DEVELOPER_DIR ?= /Applications/Xcode-beta.app/Contents/Developer
IOS_XCODEBUILD := $(IOS_DEVELOPER_DIR)/usr/bin/xcodebuild

MACOS_SWIFT_DIRS := StetMac StetMacTests StetMacUITests StetVisuals
IOS_SWIFT_DIRS := StetMobile/StetKeyboard StetMobile/StetLiveActivity StetMobile/StetMobile StetMobile/StetMobileTests StetMobile/StetMobileUITests

.PHONY: help swiftlint format format-lint lint whisper-deps build ci-build test ios-bootstrap ios-build doctor clean-derived-data release-github notary-setup

help:
	@echo "Available targets:"
	@echo "  swiftlint       Run SwiftLint"
	@echo "  format          Format Swift sources with swift-format"
	@echo "  format-lint     Lint Swift formatting with swift-format"
	@echo "  lint            Run SwiftLint and swift-format lint"
	@echo "  build           Build the macOS app"
	@echo "  ci-build        Build without code signing for CI"
	@echo "  test            Run macOS tests"
	@echo "  ios-bootstrap   Download the ignored iOS runtime frameworks"
	@echo "  ios-build       Build the iOS app for the simulator"
	@echo "  doctor          Report Xcode and project build-cache usage"
	@echo "  clean-derived-data  Remove only Stet/StetMobile build caches"
	@echo "  release-github  Build signed GitHub release artifacts"
	# @echo "  publish-github  Publish GitHub release artifacts"
	@echo "  notary-setup    Configure notarytool profile"

swiftlint:
	swiftlint lint --config .swiftlint.yml --strict --no-cache

format:
	xcrun swift-format format --in-place --recursive --parallel --configuration .swift-format $(MACOS_SWIFT_DIRS) $(IOS_SWIFT_DIRS)

format-lint:
	xcrun swift-format lint --strict --recursive --parallel --configuration .swift-format $(MACOS_SWIFT_DIRS) $(IOS_SWIFT_DIRS)

lint: swiftlint format-lint

whisper-deps:
	@echo "whisper is resolved through Swift Package Manager; no local dependency preparation is required."

build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build

ci-build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

test:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:StetTests test

ios-bootstrap:
	StetMobile/scripts/bootstrap-sherpa-runtime.sh

ios-build: ios-bootstrap
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) $(IOS_XCODEBUILD) -project StetMobile/StetMobile.xcodeproj -scheme StetMobile -sdk iphonesimulator27.0 -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

doctor:
	./scripts/xcode-storage.sh doctor

clean-derived-data:
	./scripts/xcode-storage.sh clean-project

release-github:
	./scripts/release-macos-github.sh

# publish-github:
# 	./scripts/publish-github-release.sh

notary-setup:
	./scripts/setup-notarytool-profile.sh
