---
name: feature-delivery-workflow
description: Use when coordinating feature delivery with a project manager, developer, reviewer, and QA loop from spec intake to production-ready approval.
---

# Feature Delivery Workflow

Use this skill for substantial implementation work that benefits from structured intake, a task document, developer execution, code review, and QA verification.

Do not use the full workflow for simple questions, tiny one-step edits, or exploratory discussion unless the user asks for it.

## Operating Principles

- The Project Manager owns coordination and status.
- The Developer owns implementation and fixes.
- The Reviewer owns code-review approval.
- The QA agent owns smoke-test approval.
- The user owns product direction and tradeoff decisions.
- Assume substantial completed work is intended for production launch. The workflow target is production readiness, not just local completion.
- Do not blindly accept the initial request. Challenge unclear goals, risky assumptions, missing acceptance criteria, and hidden scope.
- Prefer the simplest solution that fully satisfies the requirements. Simplicity is the goal: not simpler than necessary, but as simple as possible given the requirements.
- Do not over-engineer, introduce speculative abstractions, add unnecessary dependencies, or broaden scope unless production readiness requires it.
- Do not over-prescribe implementation. Define outcomes and constraints; let the Developer discover the best code path.
- Never use `Files Likely Involved`. Use `Discovery Notes` only for non-binding context.
- Prefer evidence from the codebase over assumptions.
- Do not declare completion until Reviewer and QA both approve production readiness, unless the user explicitly accepts remaining launch risk.

## Phase 1: Intake And Challenge

First determine whether the request is ready for implementation.

Ask clarifying questions when any of these are unclear:

- The user problem, business goal, or desired outcome.
- Acceptance criteria or observable behavior.
- Non-goals, scope boundaries, or rollout expectations.
- Data model, migration, security, privacy, authorization, billing, or irreversible behavior.
- Compatibility, performance, accessibility, or production constraints.
- Realistic data volume, latency, scalability, pagination, filtering, sorting, and production path expectations when pages, endpoints, jobs, or data-heavy flows are affected.
- A meaningful product or architecture tradeoff.

Questioning rules:

- Ask only questions that can materially change the work.
- Do not ask about facts that can be discovered by reading the repo.
- Batch questions by priority and keep them concise.
- When offering options, lead with a recommendation and explain the tradeoff.
- If the user gives enough information, proceed with clearly stated assumptions.

## Phase 2: Task Document

Create or update a task document before delegating substantial work. Prefer the repo's existing spec/task convention. If none exists, use `docs/tasks/<feature-slug>.md`.

Use this template:

```markdown
# <Feature Or Fix Name>

## Status

## Goal

## Reasoning

## Non-Goals

## Decisions

## Assumptions

## Open Questions

## Acceptance Criteria

## Implementation Tasks

## Discovery Notes

Optional non-binding starting points, related patterns, prior context, or areas worth checking. These are not implementation constraints.

## Test Plan

## Performance / Scalability Check

For affected pages, endpoints, jobs, or data flows:

- Test with realistic data volume where feasible.
- Confirm the flow still loads or completes successfully.
- Watch for obvious latency, timeouts, memory-heavy behavior, or UI degradation.
- Check for unbounded queries, N+1 behavior, missing pagination, excessive eager loading, expensive loops, unnecessary repeated work, or excessive frontend rendering.
- Record skipped checks, data-volume limitations, or remaining production risk.

## Review Checklist

## QA Smoke Checklist

## Status Log
```

Task document rules:

- Keep tasks outcome-based and independently understandable.
- Keep tasks focused on required outcomes. Do not add speculative future-proofing or optional architecture work unless explicitly justified.
- Avoid locking implementation to guessed files, classes, or components unless required.
- Record assumptions explicitly so Reviewer and QA can verify them.
- Include enough context for another agent to continue the work without asking the user to repeat themselves.

## Phase 3: Developer Handoff

Send the Developer a compact task packet:

- Link/path to the task document.
- Current goal and acceptance criteria.
- Constraints and non-goals.
- Any user decisions or assumptions.
- Meaningful milestones that should become commits, if the work is large enough.
- Documentation/header expectations from the repository instructions, including structured service headers when relevant.
- Performance/scalability expectations for affected pages, endpoints, jobs, or data-heavy flows.
- Expected tests/checks.
- Required pre-review self-verification: the Developer should run the app, boot the server, execute the CLI, or use the closest safe smoke path for the project when feasible.
- Instruction to discover existing patterns before editing.

Milestone commit rules:

- Use commits for coherent units of progress, not minute mechanical steps.
- Good milestone boundaries include schema/data changes, backend behavior, UI integration, testable workflow completion, or a meaningful review/QA fix set.
- The Developer should verify the milestone before committing it.
- The Developer must inspect status and diff before committing, stage only intended files, avoid unrelated user changes, and follow the repository's commit message style.
- If committing is unsafe or not appropriate for the repo, the Developer must explain why and continue without committing.

The Developer should return:

- What changed.
- Files changed.
- Commits created, if any.
- Documentation/header updates made, or why none were needed.
- Performance/scalability considerations and checks for affected flows, or why none were needed.
- Tests/checks run.
- Pre-review self-verification run and results, or why it could not be run.
- Blockers, risks, or follow-up questions.

Before review handoff:

- The Project Manager must check that the Developer performed at least one appropriate self-verification pass.
- If self-verification found failures, the Developer should fix them before review.
- If self-verification was skipped or impossible, the Developer must explain why and list the closest alternative checks performed.
- Do not send work to the Reviewer just because implementation is done; send it only after this self-check is complete or explicitly waived.

## Phase 4: Review Loop

After the Developer finishes, send the change context to the Reviewer.

Reviewer output must prioritize findings:

- `blocking`: must fix before QA or release.
- `major`: should fix before QA or release unless the user accepts the risk.
- `minor`: should fix if low-cost; does not necessarily block QA.
- `non-blocking`: improvement or observation.

Loop rules:

- If Reviewer reports blocking or major findings, send them to Developer for fixes.
- Missing required documentation/header updates should be treated as review findings when behavior, workflow, dependencies, API, or usage changed.
- Performance or scalability regressions in affected production paths should be treated as review findings.
- After fixes, send the updated diff back to Reviewer.
- Continue until Reviewer reports no blocking or major findings.
- If a review finding requires product direction, ask the user before implementing.

## Phase 5: QA Loop

After review approval, send the task document, acceptance criteria, test results, and review status to QA.

QA should verify as production-like as practical:

- Install/setup assumptions if relevant.
- Build or boot checks.
- Unit/integration/system tests relevant to the change.
- Smoke tests for critical user flows.
- Migration/data safety checks when relevant.
- Browser/API/CLI behavior depending on the project.
- Realistic data-volume checks for affected production paths when feasible.

QA approval standard:

- QA approval means the change appears safe to launch based on practical production-like verification.
- QA must explicitly identify unresolved launch risks, skipped checks, and coverage gaps.
- QA should only say `QA approved for production launch` when acceptance criteria are sufficiently verified and no unresolved release-blocking risks remain.

Loop rules:

- If QA reports release-blocking failures, send them to Developer.
- Developer fixes QA failures and reports tests run.
- If code changed, send the changes back to Reviewer before QA reruns.
- Continue until QA approves or the user explicitly accepts remaining risk.

## Final Handoff

The Project Manager's final response must include:

- Implementation summary.
- Reviewer status.
- QA status.
- Tests/checks run.
- Explicit production launch readiness status.
- Residual launch risks, skipped checks, or follow-ups.
- Location of the task document.
