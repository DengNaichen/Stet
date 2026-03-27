# Stet Project Constitution

## Core Principles

### I. Feature Documentation Structure

Every feature must follow the standardized documentation structure:

**Required Documents**:
- `spec.md` - Feature specification with user stories, requirements, and success criteria
- `plan.md` - Technical planning with architecture, structure, and implementation phases
- `data-model.md` - Data structures, entities, and their relationships
- `contracts/` - Public API contracts exposed to external consumers
- `tasks.md` - Implementation tasks (generated after planning phase)

**contracts/ Directory Purpose**:
- Contains ONLY the public APIs that this feature exposes to other modules
- Documents the interface contract for external consumers
- Does NOT include internal implementation details or private interfaces
- Each contract document must specify: method signatures, input/output specifications, error handling, usage examples

### II. Separation of Concerns

**Component Responsibilities**:
- Each component must have a single, well-defined responsibility
- Business logic must be separated from system APIs (CoreAudio, AVFoundation, etc.)
- UI components must be separated from business logic
- Use protocol abstractions to decouple dependencies

**Testing Strategy**:
- Business logic: Unit tests with mock dependencies
- UI components: Not unit tested (ViewModels are tested instead)
- System integration: Hardware integration tests (clearly marked)
- Correctness: Property-based tests for invariants

### III. Swift Concurrency Model (Swift 6)

**Actor Isolation**:
- UI-bound state must use `@MainActor`
- Stateless utilities should be `nonisolated`
- Cross-actor access must use thread-safe mechanisms (NSLock, actors)
- Avoid `nonisolated(unsafe)` unless absolutely necessary with proper synchronization

**Concurrency Patterns**:
- Use `@Published` properties for SwiftUI state
- Provide synchronous access methods for non-async contexts when needed
- Document thread-safety guarantees in contracts
- Use `Sendable` conformance for data passed across actors

### IV. Error Handling and Resilience

**Error Strategy**:
- Graceful degradation over crashes
- Return empty/nil on non-critical failures
- Throw errors only for critical failures that caller must handle
- Log warnings for debugging without exposing technical details to users

**Fallback Mechanisms**:
- Implement multiple fallback strategies for critical operations
- Document fallback order and retry logic
- Provide clear error messages when all fallbacks fail
- Preserve user preferences even when fallback is active

### V. Data Persistence

**UserDefaults Usage**:
- Use for lightweight user preferences only
- Define keys in centralized enum (e.g., `MacPreferences`)
- Handle read/write failures gracefully
- Never block on persistence operations

**Persistence Guarantees**:
- User preferences must survive app restarts
- Use stable identifiers (UIDs, not session IDs)
- Validate data on load, use defaults if corrupted
- Document migration strategy for schema changes

## Development Workflow

### Feature Development Process

1. **Specification Phase**:
   - Write `spec.md` with user stories and requirements
   - Get user approval before proceeding

2. **Planning Phase**:
   - Write `plan.md` with technical approach
   - Write `data-model.md` with entities and relationships
   - Write `contracts/` for public APIs
   - Perform Constitution Check

3. **Implementation Phase**:
   - Generate `tasks.md` from design documents
   - Implement in priority order (P1 → P2 → P3)
   - Write tests alongside implementation
   - Verify contracts are honored

4. **Verification Phase**:
   - All tests pass (unit, integration, property-based)
   - Performance targets met
   - Constitution compliance verified
   - User acceptance testing

### Code Review Requirements

- All changes must pass Constitution Check
- Public API changes require contract documentation updates
- Breaking changes require migration plan
- Complexity must be justified in plan.md

## Quality Standards

### Testing Requirements

**Coverage Targets**:
- Business logic: >80% code coverage
- Property-based tests for all documented invariants
- Integration tests for external API interactions
- Performance tests for critical paths

**Test Organization**:
- Unit tests: Test individual components in isolation
- Integration tests: Test component interactions
- Property tests: Verify invariants hold for all inputs
- Hardware tests: Test against real system APIs (optional in CI)

### Performance Standards

**Response Time Targets**:
- UI interactions: <50ms
- Device enumeration: <100ms
- Recording startup: <2 seconds (including fallbacks)
- State updates: <10ms

**Resource Constraints**:
- Memory: Minimal allocations in hot paths
- CPU: No blocking operations on main thread
- Battery: Stop monitoring when not needed

## Governance

**Constitution Authority**:
- This constitution supersedes all other development practices
- All features must comply with these principles
- Violations must be justified in plan.md Complexity Tracking section

**Amendment Process**:
- Amendments require documentation of rationale
- Update version number and Last Amended date
- Notify all developers of changes
- Update existing features if necessary

**Enforcement**:
- Constitution Check required in plan.md for every feature
- Code reviews must verify compliance
- Automated checks where possible (linting, tests)

**Version**: 1.0.0 | **Ratified**: 2026-03-26 | **Last Amended**: 2026-03-26
