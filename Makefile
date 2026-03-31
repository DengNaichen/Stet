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

build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build

ci-build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

test:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:StetTests test

release-github:
	./scripts/release-macos-github.sh

# publish-github:
# 	./scripts/publish-github-release.sh

notary-setup:
	./scripts/setup-notarytool-profile.sh
