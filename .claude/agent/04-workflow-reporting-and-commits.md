# 04 - Workflow, Reporting, and Commits

## Branching

- Use a dedicated branch for each task.
- Epic branch naming (Claude-first): `claude/epic-<n>-<slug>`.

## Execution Workflow

1. Understand requirements and lane constraints.
2. Propose design trade-offs before public API changes.
3. Implement incrementally with readable, extension-oriented structure.
4. Add/update tests.
5. Run required validation gates.
6. Update docs and `CHANGELOG.md`.
7. Produce step report with concrete technical detail.
8. Run autoreview for naming, compatibility, edge cases, and access control.

## Completion Discipline

A task/step is done only if:
- behavior is fully implemented end-to-end,
- no placeholders/TODO-only logic remains,
- required tests exist and pass,
- required validation gates have been executed.

## Mandatory Reporting

Each meaningful step closure should include:
- public API contract changes,
- internal implementation details,
- design rationale and rejected alternatives,
- lint/test/coverage command outputs (verbatim where practical).

## Commit Policy

- Apply selective staging.
- Keep commit messages consistent with repository convention (gitmoji prefix).
- Commit message examples:
  - `✨ feat: add XMLDateCodingStrategy.xsdDateTime support`
  - `🐛 fix: handle empty namespace prefix in XMLNamespaceResolver`
  - `🤖 chore: update CHANGELOG and agent config`
  - `:white_check_mark: test: add regression for empty attribute encoding`

## Change Log Policy

Every completed technical task must update `CHANGELOG.md` with a concise, explicit entry under `[Unreleased]`.