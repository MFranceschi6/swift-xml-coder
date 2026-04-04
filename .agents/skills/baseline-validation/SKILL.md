# Skill: baseline-validation

## Purpose

Run the required quality gates for task closure with consistent output reporting.

## Trigger Conditions

Use this skill when:
- code or tests changed,
- a task/subtask is being prepared for closure,
- quality evidence is required before commit/proposal.

## Required Inputs

- changed modules/targets,
- expected scope of verification,
- output/report destination (optional).

## Workflow Steps

1. Run mandatory baseline checks:
   - `swift build -c debug`
   - `swift test --enable-code-coverage`
   - `swiftlint lint`
2. Capture command outcomes (pass/fail + key diagnostics).
3. If a gate fails, stop closure and report precise blocker details.

## Validation/Gates

- Step cannot be considered complete without baseline check evidence.
- Failures must be reported with actionable remediation hints.

## Output Contract

Provide:
- commands executed,
- status for each gate,
- artifact/log paths if generated.

## Fallback/Failure Handling

- If environment/toolchain constraints block a command, report blocker scope and explicitly mark closure as pending.