# CLAUDE.md — SwiftXMLCoder

Open-source Swift XML codec library. SPM-only. Linux-compatible runtime. Extracted from swift-soap.

## Compatibility Lanes

`runtime-5.4` | `tooling-5.6-plus` | `macro-5.9` | `quality-5.10` | `latest`

Manifests: `Package.swift`, `Package@swift-5.6.swift`, `Package@swift-5.9.swift`,
`Package@swift-6.0.swift`, `Package@swift-6.1.swift`

## Required Validation (before any task closure)

```sh
swift build -c debug
swift test --enable-code-coverage
swiftlint lint
```

## Scope

Work is scoped to **this repository only**. No changes to external dependencies, transport layers, SOAP concerns, or other repos unless explicitly asked.

## Workflow

- Search with Grep first, then Read only the specific files needed.
- After refactors touching multiple files, run the full test suite immediately.
- When continuing a multi-session task, read `.claude/plans/active-plan.md` and the last CHANGELOG entry to orient.

## Design Rules

- No raw strings for namespace URIs, element names, or coding keys — use typed enums or `static let`.
- Typed errors (`enum` + `Error`). Stable contracts. Generic fallback case on public error enums.
- Dual `#if swift(>=6.0)` typed-throws branches for throw-capable public methods.
- `internal` by default; `public` only when intentional.
- All public types must be `Sendable`. Prefer immutable value types.
- Type declarations in `Type.swift`. Extended logic in `Type+Logic.swift`, `Type+Codable.swift`.
- Bug fixes must include regression tests. Features must cover core behavior and edge cases.
- Tests must be deterministic and isolated.
- All source comments and documentation in English.

## Module Layout

| Module | Purpose |
|--------|---------|
| `SwiftXMLCoder` | Core encoder/decoder, tree model, parser, writer, canonicalization |
| `SwiftXMLCoderCShim` | C interop shim for libxml2 |
| `CLibXML2` | System library wrapper for libxml2 |
| `XMLCoderCompatibility` | Cross-version compatibility shims |
| `SwiftXMLCoderOwnership6` | Swift 6.0+ ownership semantics |
| `SwiftXMLCoderMacros` | Public macro facade (`@XMLCodable`, `@XMLAttribute`, `@XMLElement`) |
| `SwiftXMLCoderMacroImplementation` | Macro compiler plugin (swift-syntax) |
| `SwiftXMLCoderTestSupport` | Spy encoders/decoders, contract harness, canonicalizer probes |

## Safety

- Never revert unrelated local changes.
- No new dependencies without documented rationale (problem, alternatives, license/security, rollback).
- Current approved: `swift-log`, `swift-syntax`.
- Always update `CHANGELOG.md` for completed technical tasks.
- Gitmoji commit prefix. Selective staging.
- Branch naming: `claude/epic-<n>-<slug>`.

## Skills

Invoke with `/skill-name`. Definitions in `.claude/skills.md`.

| Skill | When to invoke |
| --- | --- |
| `baseline-validation` | Before any task closure — run build/test/lint gates |
| `step-report-and-changelog` | When work is functionally complete — step report + CHANGELOG |
| `commit-checkpoint` | At a meaningful checkpoint — safe commit preparation |
| `plan-status` | At the start of any session — check plan status and orient |

## Plans

- Active plan: `.claude/plans/active-plan.md`
- Enterprise roadmap (read on demand): `.claude/plans/enterprise-roadmap.md`
