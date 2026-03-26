# Requirements Document

## Introduction

This document defines the requirements for the **app-branch** feature - a standalone macOS module that provides real-time detection of the currently active/foreground application. The module is designed to be independent from the main application thread, allowing other components or external systems to query the current frontmost application without direct coupling.

## Glossary

- **Foreground Application**: The application that is currently receiving user input and is visible on screen
- **Active App**: Same as foreground application - the app currently in focus
- **Bundle Identifier**: A unique string identifier for a macOS application (e.g., "com.apple.Safari")
- **NSWorkspace**: The AppKit API for interacting with the desktop environment
- **App Branch Group**: A user-defined collection of applications with associated prompts for text enhancement
- **Standalone Module**: A self-contained component that operates independently of the main application lifecycle

## Requirements

### Requirement 1: Foreground App Detection

**User Story:** As a developer, I want to detect which application is currently in the foreground, so that I can apply context-aware behavior in my application.

#### Acceptance Criteria

1. THE AppBranchMonitor SHALL provide a method to retrieve the currently foreground application
2. WHEN the foreground application changes, THE AppBranchMonitor SHALL notify registered observers
3. THE AppBranchMonitor SHALL return the bundle identifier of the foreground application
4. THE AppBranchMonitor SHALL return the localized name of the foreground application

### Requirement 2: Real-Time Monitoring

**User Story:** As a user, I want the module to continuously monitor app changes in real-time, so that I always have accurate information about the current application.

#### Acceptance Criteria

1. WHEN the user switches to a different application, THE AppBranchMonitor SHALL detect the change within 500 milliseconds
2. THE AppBranchMonitor SHALL subscribe to NSWorkspace notifications for active application changes
3. WHILE the module is running, THE AppBranchMonitor SHALL continuously monitor without manual polling

### Requirement 3: Standalone Operation

**User Story:** As a system architect, I want this module to operate independently from the main thread, so that it does not block or depend on the primary application logic.

#### Acceptance Criteria

1. THE AppBranchMonitor SHALL be instantiable with injectable dependencies for testing
2. THE AppBranchMonitor SHALL run observer callbacks on a background queue
3. THE AppBranchMonitor SHALL provide callback mechanisms that are thread-safe using locks
4. THE AppBranchMonitor SHALL not block the main thread during app change detection

### Requirement 4: Application Information Retrieval

**User Story:** As a developer, I want to retrieve detailed information about the foreground application, so that I can make informed decisions based on the active app.

#### Acceptance Criteria

1. THE AppBranchMonitor SHALL provide access to the NSRunningApplication object of the foreground app (when available)
2. THE AppBranchMonitor SHALL provide the process identifier (PID) of the foreground application
3. THE AppBranchMonitor SHALL indicate whether the foreground app is the module's own host application
4. THE AppBranchMonitor SHALL classify the foreground app as human-targeted or AI-targeted via AppAudience

### Requirement 5: Observer Pattern Support

**User Story:** As a developer, I want to register for notifications when the foreground app changes, so that I can react to app switches programmatically.

#### Acceptance Criteria

1. THE AppBranchMonitor SHALL support registering observer callbacks for app change events
2. THE AppBranchMonitor SHALL support unregistering observer callbacks
3. THE observer callback SHALL receive the new foreground application information
4. THE AppBranchMonitor SHALL support multiple concurrent observers

### Requirement 6: Self-App Exclusion

**User Story:** As a user, I want the module to optionally exclude its own host application from detection, so that I can focus on external applications only.

#### Acceptance Criteria

1. WHERE exclusion is enabled, THE AppBranchMonitor SHALL allow configuring a bundle identifier to exclude
2. WHERE the excluded app is in the foreground, THE AppBranchMonitor SHALL return the previously active application or nil

### Requirement 7: Module Interface

**User Story:** As a developer, I want a clean, simple API to integrate this module, so that adoption is straightforward.

#### Acceptance Criteria

1. THE AppBranchMonitor SHALL expose a shared instance for convenience access
2. THE AppBranchMonitor SHALL provide a startMonitoring method to begin tracking
3. THE AppBranchMonitor SHALL provide a stopMonitoring method to halt tracking
4. THE AppBranchMonitor SHALL provide a currentApp property to query the active app synchronously

## Non-Functional Requirements

### Performance

- App change detection latency SHALL NOT exceed 500ms
- Memory footprint SHALL be minimal (less than 5MB)
- CPU usage during idle monitoring SHALL be negligible

### Compatibility

- THE module SHALL support macOS 12.0 (Monterey) and later
- THE module SHALL be compatible with both SwiftUI and AppKit applications

### Testing

- THE module SHALL include unit tests for core functionality
- THE module SHALL include integration tests for notification handling