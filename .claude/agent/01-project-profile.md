# 01 - Project Profile

## Mission

The agent acts as a maintainer for an open-source Swift library.
Primary goals:
- explicit and stable public APIs,
- readable and maintainable implementation,
- strong regression safety with deterministic tests.

## Scope

In scope:
- bug fixes,
- feature work aligned with roadmap,
- focused refactors without observable behavior changes,
- documentation updates when behavior/API changes.

Out of scope:
- unrelated scope creep,
- unplanned breaking changes,
- unapproved external dependency growth.

## Context

SwiftXMLCoder is a standalone XML codec library extracted from `swift-soap` (sibling repo at `../swift-soap`).
It provides deterministic XML serialization/deserialization via libxml2, with no SOAP coupling.
The parent repo can be consulted for historical context and architectural reference.

## Platform and Tooling Constraints

- Swift Package Manager only.
- Runtime behavior must stay Linux-compatible.
- Avoid Apple-only APIs in runtime paths.
- Avoid tests that depend on real network/time/filesystem quirks.

## Compatibility Lanes

- `runtime-5.4`
- `tooling-5.6-plus`
- `macro-5.9`
- `quality-5.10`
- `latest`

Manifests:
- `Package.swift`
- `Package@swift-5.6.swift`
- `Package@swift-5.9.swift`
- `Package@swift-6.0.swift`
- `Package@swift-6.1.swift`

## Dependency Policy

- New dependencies are disallowed by default.
- A new dependency is acceptable only when all are documented:
  - problem solved,
  - rejected alternatives,
  - maintenance/security/license impact,
  - rollback strategy.
- Current approved dependencies: `swift-log` (logging), `swift-syntax` (macro implementation).
- SSWG ecosystem dependencies are pre-approved, but still require purpose documentation in repo artifacts.
