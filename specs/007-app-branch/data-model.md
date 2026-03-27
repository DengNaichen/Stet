# Data Model: App Branch

## Overview

The `app-branch` feature is built around a small runtime model:

- the currently detected app
- a normalized app record exposed to the rest of the app
- a derived app-audience classification
- observer registrations for change notifications
- transient monitor state that ties the pieces together

This feature does not persist app-branch history.

## Core Entities

### 1. Foreground App Snapshot

Represents the current detected foreground app before it is normalized for downstream use.

**Fields**

- `bundleIdentifier`: optional bundle identifier from the workspace snapshot
- `localizedName`: optional display name from the workspace snapshot
- `processIdentifier`: process identifier for the frontmost app
- `runningApplication`: optional live app reference when one is available

**Purpose**

- Serves as the input to active-app resolution.
- Preserves the live app reference when it exists.

**Notes**

- This is a runtime snapshot, not a persisted model.
- Missing fields are expected and must be handled gracefully.

---

### 2. App Info

Represents the normalized app record that the monitor returns to consumers.

**Fields**

- `bundleIdentifier`
- `localizedName`
- `processIdentifier`
- `isOwnHostApplication`
- `runningApplication`

**Purpose**

- Provides the user-visible snapshot of the active app.
- Carries enough information for downstream logic to branch on the current app.

**Relationships**

- Derived from `Foreground App Snapshot`.
- Feeds `App Audience Classification`.
- Returned by `AppBranchMonitor.currentApp`.

**Invariants**

- `bundleIdentifier` is non-empty when an `AppInfo` exists.
- `localizedName` remains readable even if the workspace did not provide one.
- Equality is based on the user-visible snapshot fields, not on the live `runningApplication` object identity.

---

### 3. App Audience Classification

Represents the derived routing category used by downstream cleanup and related app-context behavior.

**Values**

- `human`
- `ai`

**Purpose**

- Identifies whether the active app should steer downstream prompt behavior toward human-oriented or AI-oriented cleanup.

**Relationships**

- Derived from `App Info`.
- Consumed by dictation cleanup and other downstream app-context behavior.

**Invariants**

- Classification is derived, not user-entered.
- The current implementation uses name and bundle-identifier matching rules.

---

### 4. Observer Registration

Represents a single registered callback for app-branch updates.

**Fields**

- `id`: stable UUID used for removal

**Purpose**

- Allows multiple consumers to listen for app changes independently.

**Relationships**

- Stored inside monitor runtime state.
- Removed by `AppBranchMonitor.removeObserver(_:)`.

**Invariants**

- Observer IDs are unique.
- Removing an unknown ID is a no-op.

---

### 5. Monitor Runtime State

Represents the transient in-memory state owned by the monitor.

**Fields**

- `isMonitoring`
- `excludedBundleID`
- `currentNonExcludedApp`
- `previousNonExcludedApp`
- `observers`

**Purpose**

- Tracks monitoring lifecycle and exclusion behavior.
- Preserves the last non-excluded app so exclusion can fall back cleanly.

**Relationships**

- Owns the observer registration map.
- Uses `Foreground App Snapshot` to resolve `AppInfo`.

**Invariants**

- Only one monitoring session should be active at a time.
- The exclusion rule never mutates the underlying workspace snapshot.
- `currentNonExcludedApp` and `previousNonExcludedApp` are runtime-only and are not persisted across launches.

## State Transitions

1. The workspace emits a frontmost-app activation change.
2. The monitor resolves a new `AppInfo` from the raw snapshot.
3. If the current app matches the excluded bundle identifier, the monitor returns the most recent non-excluded app or `nil`.
4. Registered observers receive the resolved value asynchronously.
5. The current app signal is then available to downstream consumers such as speech cleanup and session-level app targeting.

## Persistence

- No entity in this feature is persisted by the feature itself.
- The monitor does not write user preferences, app history, or observer state to disk.
- Any caller that wants a persistent exclusion rule must store that setting elsewhere.
