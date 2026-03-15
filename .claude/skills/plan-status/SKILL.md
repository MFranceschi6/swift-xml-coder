# Skill: plan-status

## Purpose

Orient to the current state of the 1.0 release plan at the start of a session or after a context switch. Produces a concise status summary and identifies the next actionable task.

## Trigger Conditions

Use this skill when:
- starting a new session on this project,
- resuming work after a break,
- asked "where are we?" or "cosa manca?" or similar orientation questions.

## Required Inputs

None. The skill reads the plan and repo state autonomously.

## Workflow Steps

1. Read the release plan: `.claude/plans/release-1.0.md`
2. Read `CHANGELOG.md` — the `[Unreleased]` section shows what has been completed since 0.1.0.
3. Check recent git commits: `git log --oneline -10`
4. Cross-reference completed CHANGELOG entries and commits against the plan epics (A, B, C, D, E, E-bis, F).
5. Produce a status table:
   - Epic | Status (✅ Done / 🔄 In Progress / ⏳ Pending) | Notes
6. Identify the highest-priority incomplete item and state it as the recommended next action.

## Validation/Gates

- Do not guess status — derive it from CHANGELOG entries and git history only.
- If status is ambiguous, mark as ⏳ Pending and note the uncertainty.

## Output Contract

Provide:
- Status table for all epics
- Recommended next task (single, specific, actionable)
- Any blockers or dependencies that affect sequencing

## Fallback/Failure Handling

- If the plan file is missing, report it and suggest re-running the planning session.
- If git history is unavailable, derive status from CHANGELOG only.