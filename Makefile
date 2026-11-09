IOS_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DOCS_BOOTSTRAP_PYTHON ?= python3.11
DOCS_PYTHON ?= linter/.venv/bin/python
CI_XCODEBUILD_FLAGS ?=
# Xcode owns the content-addressed compilation cache; each checkout keeps its
# own DerivedData and mutable package artifacts. Set NO for comparison runs.
MACOS_COMPILATION_CACHE ?= YES
MACOS_CACHE_FLAGS = COMPILATION_CACHE_ENABLE_CACHING=$(MACOS_COMPILATION_CACHE) -showBuildTimingSummary

IOS_XCODEBUILD := $(IOS_DEVELOPER_DIR)/usr/bin/xcodebuild

# These regressions deliberately block MainActor while background audio work runs.
# Keep them out of the process that runs other tests' wall-clock polling deadlines.
MACOS_MAIN_ACTOR_ISOLATION_TESTS := \
	StetTests/AudioM4AWriterTests/encodingCanFinishWhileMainActorIsOccupied() \
	StetTests/DefaultAudioPostProcessorTests/speechProcessingCanFinishWhileMainActorIsOccupied() \
	StetTests/MacRecordingFileStabilizerTests/existingFileCanStabilizeWhileMainActorIsOccupied()
MACOS_TEST_COMMAND = xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' $(MACOS_CACHE_FLAGS) $(CI_XCODEBUILD_FLAGS)

MACOS_SWIFT_DIRS := StetMac StetMacTests StetMacUITests StetVisuals
IOS_SWIFT_DIRS := StetMobile/StetKeyboard StetMobile/StetLiveActivity StetMobile/StetMobile StetMobile/StetMobileTests StetMobile/StetMobileUITests

.PHONY: docs-lint docs-lint-setup docs-lint-test help swiftlint format format-lint lint whisper-deps build ci-build test test-mainactor-isolation ios-bootstrap ios-build setup-worktree doctor clean-derived-data release-github notary-setup

help:
	@echo "Available targets:"
	@echo "  swiftlint       Run SwiftLint"
	@echo "  format          Format Swift sources with swift-format"
	@echo "  format-lint     Lint Swift formatting with swift-format"
	@echo "  lint            Run Swift and documentation link checks"
	@echo "  docs-lint       Check local Markdown links and heading anchors (offline)"
	@echo "  docs-lint-setup Install pinned link-checker dependencies (Python 3.11)"
	@echo "  docs-lint-test  Test the link checker"
	@echo "  build           Build the macOS app"
	@echo "  ci-build        Build without code signing for CI"
	@echo "  test            Run macOS tests, then MainActor isolation regressions separately"
	@echo "  test-mainactor-isolation Run only the MainActor obstruction regressions"
	@echo "  ios-bootstrap   Download the ignored iOS runtime frameworks"
	@echo "  ios-build       Build the iOS app for the simulator"
	@echo "  setup-worktree  Prepare tools; reuse validated worktree caches"
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

lint: swiftlint format-lint docs-lint

docs-lint-setup:
	$(DOCS_BOOTSTRAP_PYTHON) -m venv linter/.venv
	$(DOCS_PYTHON) -m pip install --require-hashes --only-binary=:all: -r linter/requirements.txt

docs-lint:
	$(DOCS_PYTHON) -B linter/lint.py

docs-lint-test:
	$(DOCS_PYTHON) -B -m unittest discover -s linter/tests -v

whisper-deps:
	@echo "whisper is resolved through Swift Package Manager; no local dependency preparation is required."

build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' $(MACOS_CACHE_FLAGS) $(CI_XCODEBUILD_FLAGS) build

ci-build:
	xcodebuild -project Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' $(MACOS_CACHE_FLAGS) $(CI_XCODEBUILD_FLAGS) build

test:
	$(MACOS_TEST_COMMAND) -only-testing:StetTests $(foreach test,$(MACOS_MAIN_ACTOR_ISOLATION_TESTS),'-skip-testing:$(test)') test
	$(MAKE) test-mainactor-isolation

test-mainactor-isolation:
	$(MACOS_TEST_COMMAND) $(foreach test,$(MACOS_MAIN_ACTOR_ISOLATION_TESTS),'-only-testing:$(test)') test

ios-bootstrap:
	StetMobile/scripts/bootstrap-sherpa-runtime.sh

ios-build: ios-bootstrap
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) $(IOS_XCODEBUILD) -project StetMobile/StetMobile.xcodeproj -scheme StetMobile -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

setup-worktree:
	./scripts/setup-worktree --if-needed

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
