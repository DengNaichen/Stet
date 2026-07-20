# Data Model: Permission Management

## Overview

This document describes the domain state that drives permission management in Stet on macOS. It focuses on feature-level entities and relationships rather than framework-specific implementation details.

## Core Entities

### PermissionStatus

Represents the current state of a single permission signal.

**States**:
- `allowed`
- `notRequested`
- `needsAccess`
- `unavailable`

**Derived Behavior**:
- `needsAttention` is true unless the status is `allowed`
- `canRequestInApp` is true only for `notRequested`
- `text` is the user-facing status label shown in the UI

### PermissionSnapshot

Represents the current combined permission state used by the app.

**Key Attributes**:
- `microphoneStatus`
- `inputControlStatus`
- `hasRequiredPermissions`

**Derived Behavior**:
- `hasRequiredPermissions` is true only when both required permissions are allowed
- The onboarding UI and runtime gate both derive from this same combined state

### OnboardingPermissionStep

Represents the onboarding surface that explains and gates the required permissions.

**Key Attributes**:
- `microphoneStatusText`
- `inputControlStatusText`
- `microphoneRecoveryAction`
- `inputControlRecoveryAction`
- `canContinue`

**Invariants**:
- The step remains visible until required permissions are available or the user leaves onboarding
- Continue is not enabled until the combined permission snapshot is satisfied

### RuntimePermissionGate

Represents the standalone recovery surface shown when the app cannot start a permission-dependent action.

**Key Attributes**:
- `messageText`
- `microphoneRecoveryAction`
- `inputControlRecoveryAction`
- `isVisible`
- `shouldDismiss`

**Invariants**:
- Only one equivalent runtime gate should be visible at a time
- The gate disappears automatically when required permissions become available
- The gate does not model a full permission dashboard

### PermissionRecoveryAction

Represents a user-facing action that restores access or navigates to the relevant system recovery path.

**Variants**:
- request microphone access in-app when possible
- open System Settings for microphone access when in-app request is not possible
- request input control / accessibility access through the existing app path

## Relationships

- `PermissionSnapshot` feeds both `OnboardingPermissionStep` and `RuntimePermissionGate`.
- `MacPermissionsCoordinating` provides the live state and recovery actions consumed by the onboarding view model and runtime gate view model.
- `MacAppSessionController` consults the combined permission state before permission-dependent actions begin.

## State Transitions

### Permission Status Transitions

```text
notRequested -> allowed
needsAccess -> allowed
allowed -> needsAccess
allowed -> unavailable
```

These transitions are driven by system permission state and app refresh events.

### Runtime Gate Transitions

```text
idle without gate
  -> blocked action while idle
  -> gate visible

gate visible
  -> permissions restored
  -> gate dismissed

gate visible
  -> user dismisses without fixing permissions
  -> gate hidden until the next blocked action
```

### Onboarding Step Transitions

```text
permission step active
  -> permissions satisfied
  -> continue becomes available

permission step active
  -> permissions missing
  -> continue remains disabled
```

## Persistence Model

Persisted data in the current implementation is intentionally small:

- Permission grant state itself is not persisted
- `PermissionStatus` values are derived from the system at runtime
- Onboarding completion is persisted elsewhere in the app and is not a permission grant record

The following state is not persisted:

- current runtime gate visibility
- current permission status labels
- current permission recovery button labels
- current permission refresh state

## Invariants

- A permission-dependent action must not proceed when the combined permission snapshot is unsatisfied.
- The runtime permission gate must not interrupt an active recording or processing session.
- Permission state should refresh when the app becomes active again.
- Permission grant status is derived from system APIs, not from a local shadow copy.
- The onboarding permission step and runtime gate use the same underlying permission truth, even though they present it differently.

## Out Of Scope For This Data Model

The following are implementation details rather than feature data model concerns:

- window placement and AppKit styling
- exact system settings URL mechanics
- Combine subscription mechanics
- logging and instrumentation details
