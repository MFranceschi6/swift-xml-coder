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

Work is scoped to **this repository only**. Do not suggest changes to external dependencies, transport layers, SOAP concerns, or other repos unless explicitly asked. When in doubt, narrow scope rather than expand it.

## Workflow

- Search with Grep first, then Read only the specific files needed. Never read files one-by-one sequentially when Grep can identify the relevant subset.
- After any refactor touching multiple files, run the full test suite immediately and fix all failures before reporting completion. Never report a task as done with pending test failures.
- When continuing a multi-session task, read the release plan at `.claude/plans/release-1.0.md` and the last CHANGELOG entry to orient before acting.

## Design Rules

- No raw strings for namespace URIs, element names, or coding keys — use typed `String`-backed enums or `static let` constants.
- Typed errors (`enum` + `Error`). Stable error contracts. Include a generic fallback case on public error enums.
- Dual `#if swift(>=6.0)` typed-throws branches for all throw-capable public methods.
- `internal` by default; `public` only when intentional.
- Bug fixes must include regression tests. Features must cover core behavior and edge cases.
- Tests must be deterministic and isolated (no real network/time/filesystem dependencies).

## Safety

- Never revert unrelated local changes.
- No new dependencies without documented rationale (problem, alternatives, license/security, rollback).
- Always update `CHANGELOG.md` for completed technical tasks.
- Gitmoji commit prefix. Selective staging.
- Branch naming: `claude/epic-<n>-<slug>`.

## Skills

Invoke with `/skill-name`. Details in `.claude/skills/<name>/SKILL.md`.

| Skill | When to invoke |
| --- | --- |
| `baseline-validation` | Before any task closure — run build/test/lint gates |
| `step-report-and-changelog` | When work is functionally complete — step report + CHANGELOG |
| `commit-checkpoint` | At a meaningful checkpoint — safe commit preparation |
| `plan-status` | At the start of any session — check release plan status and orient to next task |

## Deep-Dive Policy (read on demand only)

- `.claude/agent/01-project-profile.md` — scope, platform, dependency policy
- `.claude/agent/02-engineering-standards.md` — API design, file structure, concurrency
- `.claude/agent/03-validation-and-quality-gates.md` — coverage targets, test isolation
- `.claude/agent/04-workflow-reporting-and-commits.md` — workflow, branching, reporting
- `.claude/agent/05-skills-and-context-organization.md` — skill authoring rules
