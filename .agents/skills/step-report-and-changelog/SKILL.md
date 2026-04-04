# Skill: step-report-and-changelog

## Purpose

Close a technical step with complete reporting and changelog updates.

## Trigger Conditions

Use this skill when a task/subtask is functionally complete and ready for closure.

## Required Inputs

- summary of implemented changes,
- API changes (if any),
- validation results (build/test/lint),
- known residual risks.

## Workflow Steps

1. Build a step report using `../_shared-templates/step-report-template.md` as baseline structure.
2. Include:
   - public API contract changes,
   - implementation details,
   - design rationale and rejected alternatives,
   - validation outputs and artifact paths.
3. Add/extend `CHANGELOG.md` in `[Unreleased]` with concise technical entries.
4. Ensure report and changelog align on actual delivered behavior.

## Validation/Gates

- No step is considered closed without an updated `CHANGELOG.md` entry.
- Report must be technical, not a high-level summary only.

## Output Contract

Provide:
- changelog entries added/updated,
- step report (inline or file reference),
- residual risks/follow-ups (if any).

## Fallback/Failure Handling

- If evidence is missing (e.g., absent test output), mark closure as blocked and list missing artifacts.