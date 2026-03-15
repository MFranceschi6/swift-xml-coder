# Skill: commit-checkpoint

## Purpose

Prepare and validate a safe checkpoint commit following repository conventions.

## Trigger Conditions

Use this skill when a meaningful technical checkpoint is ready to commit.

## Required Inputs

- checkpoint scope,
- files intended for commit,
- proposed commit message.

## Workflow Steps

1. Stage only intended files (selective staging — never `git add .`).
2. Verify all staged changes are intentional and unrelated changes remain unstaged.
3. Validate commit message format:
   - gitmoji prefix + concise imperative summary.
   - Example: `✨ feat: add XMLDateCodingStrategy.xsdDateTime support`
4. Confirm `CHANGELOG.md` contains the relevant entry under `[Unreleased]`.
5. Run baseline validation if not already done.
6. Create the commit.

## Validation/Gates

- Commit message must satisfy gitmoji policy.
- Unrelated modified files must remain unstaged.
- `CHANGELOG.md` must have been updated.

## Output Contract

Provide:
- staged file list,
- commit message used,
- gate results.

## Fallback/Failure Handling

- If validation fails, stop and provide concrete remediation steps before retrying.