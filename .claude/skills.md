# Skills

## baseline-validation

**When**: before any task closure, when code or tests changed.

1. `swift build -c debug`
2. `swift test --enable-code-coverage`
3. `swiftlint lint`

Report: commands executed, status for each gate, blockers if any. Stop closure on failure.

## step-report-and-changelog

**When**: task/subtask is functionally complete and ready for closure.

1. Build step report: API changes, implementation details, design rationale, validation outputs.
2. Update `CHANGELOG.md` `[Unreleased]` with concise technical entries.
3. Ensure report and changelog align on delivered behavior.

No step is closed without an updated CHANGELOG entry.

## commit-checkpoint

**When**: meaningful technical checkpoint ready to commit.

1. Stage only intended files (selective — never `git add .`).
2. Verify unrelated changes remain unstaged.
3. Gitmoji prefix + concise imperative summary.
4. Confirm `CHANGELOG.md` has the relevant entry.
5. Run baseline-validation if not already done.
6. Create the commit.

## plan-status

**When**: start of session, resuming after break, orientation questions.

1. Read `.claude/plans/active-plan.md`.
2. Read `CHANGELOG.md` `[Unreleased]` section.
3. Check `git log --oneline -10`.
4. Cross-reference completed entries against plan phases.
5. Produce status table (Phase | Status | Notes).
6. Identify highest-priority incomplete item as next action.
7. If relevant, check `.claude/plans/enterprise-roadmap.md` for broader context.
