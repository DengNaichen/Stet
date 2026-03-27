# Stet Project Constitution

## Core Principles

### I. Feature Documentation Structure

Every feature must follow the standardized documentation structure:

**Required Documents**:

- `spec.md` - Feature specification with user stories, requirements, and success criteria
- `plan.md` - Feature design document with the technical approach, structure, and design decisions
- `data-model.md` - Data structures, entities, and their relationships
- `contracts/` - Public API contracts exposed to external consumers
- `tasks.md` - Execution task list generated after the design phase

**Optional Supporting Documents**:

- `research.md` - Decision rationale, investigation notes, and supporting research when a feature needs exploratory work; it is optional and may live outside the feature folder when the research is cross-cutting or maintained in another repository

**contracts/ Directory Purpose**:

- Contains ONLY the public APIs that this feature exposes to other modules
- Documents the interface contract for external consumers
- Does NOT include internal implementation details or private interfaces
- Each contract document must specify: method signatures, input/output specifications, error handling, usage examples

### II. Documentation Quality

**Specification**:

- `spec.md` MUST be written as a product specification.
- It MUST define prioritized and independently testable user stories, user-visible requirements, relevant edge cases, measurable and technology-agnostic success criteria, and explicit assumptions.
- It MUST avoid implementation detail unless that detail directly affects user-visible behavior or feature scope.

**Data Model**:

- `data-model.md` MUST describe the feature's core domain entities, the key attributes that matter to product behavior, the relationships between entities, relevant state transitions, and the invariants that must always hold.
- It MUST identify what data is persisted and which identifiers must remain stable.
- It MUST avoid implementation-specific detail such as API contracts, framework types, storage engine mechanics, or internal class structure unless those details directly affect the domain model.

**Contracts**:

- `contracts/` MUST describe only the public interfaces a feature exposes across module or system boundaries.
- Each contract MUST define the consumer-visible interface, expected inputs, outputs, error behavior, constraints, and usage expectations.
- It MUST avoid internal implementation detail, private structures, and framework wiring that are not part of the external contract.
- If an interface is not consumed across a boundary, it SHOULD NOT be documented in `contracts/`.

**Plan**:

- `plan.md` serves as the feature's design document and MUST translate the approved specification into a concrete technical approach.
- It MUST define the implementation strategy, technical context, constitution check, intended project structure, and any justified complexity required for delivery.
- It MUST not replace the spec, the data model, the contracts, or the task list.

**Tasks**:

- `tasks.md` MUST be generated from the current specification, plan, data model, and contracts using the task template's structure.
- It MUST serve as the execution plan by organizing work into clear, executable tasks that map back to user stories and support incremental delivery.
- `tasks.md` is a disposable execution artifact rather than a long-lived source of truth and MAY be regenerated whenever scope, design, or sequencing changes.
- It MUST not contain product requirements, domain modeling, or technical design detail that belongs in other documents.

**Research**:

- `research.md` is optional and exists to capture decision rationale, investigation notes, and supporting research when a feature needs exploratory work.
- Research MAY live outside the feature folder when it is cross-cutting or maintained in another repository.

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

**Version**: 0.1.5 | **Ratified**: 2026-03-26 | **Last Amended**: 2026-03-26
