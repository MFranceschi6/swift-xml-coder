# 05 - Skills and Context Organization (Claude Code)

## Goal

Keep operational context small, composable, and deterministic by splitting reusable workflows into repository skills.

## Repository Skill Layout

Each skill must live in:
- `.claude/skills/<skill-name>/SKILL.md`

Optional companion folders per skill:
- `references/` for focused supporting docs,
- `templates/` for reusable output formats,
- `scripts/` for repeatable command wrappers.

## Required SKILL.md Sections

Each skill must define at least:
- Purpose
- Trigger Conditions
- Required Inputs
- Workflow Steps
- Validation/Gates
- Output Contract
- Fallback/Failure Handling

## Skill Activation Rules

- Activate a skill when the user request matches its trigger.
- If multiple skills apply, choose the minimum set and state execution order.
- Do not load all reference files; load only the minimum needed to execute safely.

## Progressive Context Loading

1. `CLAUDE.md` is auto-loaded — contains all routine policy.
2. Load only the relevant module(s) in `.claude/agent/` when the task requires deep-dive detail.
3. Load only selected `SKILL.md` files needed by the request.
4. Load referenced files on demand, not preemptively.

## Context Hygiene Rules

- Prefer concise summaries over large copy-paste blocks.
- Avoid broad repository scans unless required.
- Keep temporary notes in `.claude/` and stable rules in tracked docs.

## When to Add a New Skill

Add a skill when a workflow is:
- repeated frequently,
- non-trivial,
- error-prone without a checklist,
- dependent on project-specific commands or constraints.

Do not add a new skill for one-off tasks.

## Hooks vs Skills

- Use hooks for deterministic safety gates that must run automatically (`.githooks`).
- Use skills for decision-heavy workflows requiring context and judgement.
- Prefer extending existing hooks before creating new ones.
