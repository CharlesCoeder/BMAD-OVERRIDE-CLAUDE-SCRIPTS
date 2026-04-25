---
name: 'enhanced-automated-sprint'
description: 'Run the full BMAD pipeline (BMAD 6.4-targeted) for multiple stories in an epic. Breaks stories into manageable tasks, tracks progress with TaskCreate/TaskUpdate, and uses focused agents for context efficiency. Supports parallel story execution. Unattended-by-default with anti-leak commit messages, auto-commit (incl. submodules), and a deferred-decisions log.'
---

<!-- BMAD 6.2.0 → 6.4.0 skill-reference audit (do not delete; future upgrades use this as a baseline)

| Step | 6.2.0 invocation | 6.4 status | 6.4 invocation / replacement |
|------|------------------|-----------|------------------------------|
| 1    | /bmad-bmm-create-story ${SID}                  | RENAMED                | /bmad-create-story ${SID}                                                            |
| 3    | /bmad-bmm-create-story validate ${SID}         | REMOVED (no `validate` subcommand) | Fresh-context Opus sub-agent that executes BMAD's bmad-create-story/checklist.md     |
| 4    | /bmad-bmm-qa-automate TDD ${SID} yolo          | REMOVED (qa-automate gone; Quinn QA → Amelia in 6.3.0; Amelia does Kent-Beck TDD inside dev-story) | DROPPED (defer unit TDD into bmad-dev-story Step 5)                                  |
| 4b   | /bmad-qa-generate-e2e-tests ${SID}             | KEPT                   | /bmad-qa-generate-e2e-tests ${SID}  (now renumbered to Step 4)                       |
| 5    | /bmad-bmm-dev-story ${SID} yolo                | RENAMED                | /bmad-dev-story ${SID} yolo                                                          |
| 7    | /bmad-bmm-code-review ${SID} yolo              | RENAMED (still consolidates Blind Hunter + Edge Case Hunter + Acceptance Auditor) | /bmad-code-review ${SID} yolo                                                        |
| 10   | /bmad-bmm-qa-automate TRACE ${SID} yolo        | REMOVED (redundant with Step 7 Acceptance Auditor) | DROPPED                                                                              |
| 11   | /bmad-bmm-sprint-status                        | RENAMED                | /bmad-sprint-status  (now renumbered to Step 10)                                     |
| ER   | /bmad-bmm-correct-course                       | RENAMED                | /bmad-correct-course                                                                 |

Net pipeline shape: 11 steps → 9 steps. Final ordering: 1 Create story → 2 Elicitation → 3 Validate (fresh-context BMAD-checklist) → 4 E2E TDD (red phase) → 5 Implement → 6 Merge → 7 Consolidated review → 8 Fix → 9 Merge fixes (+ auto-commit) → 10 Sprint status.

New defaults baked into 6.4.0 (no opt-out, this fork is personal):
- Unattended-by-default execution (only ambiguous merge conflicts pause)
- Auto-commit per story at Step 9 (submodule-first, then main repo; never auto-pushes)
- Deferred-decisions log artifact at {implementation_artifacts}/sprint-epic-${EPIC_ID}-deferred-decisions.md
- Codebase anti-leak rules (no BMAD/story-ID references in code or main-repo commits)
- Phase 0 epic-context cache compiled once and reused across Steps 1, 5, 7
-->

# Enhanced Automated Sprint Pipeline

> **TL;DR for humans:** This skill automates the entire dev lifecycle for multiple stories in an epic. You give it an epic ID (and optionally specific story IDs), and it runs each story through: **create -> refine -> validate (fresh-context BMAD checklist) -> write E2E tests -> implement -> consolidated code review -> fix issues -> merge fixes (auto-commit) -> update sprint status**. BMAD 6.4's `/bmad-code-review` runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally — no separate adversarial/edge-case steps needed. Stories can run in parallel when independent. **Unattended by default**: every former pause point auto-resolves with best-judgment and logs to a deferred-decisions doc; the only hard pause is ambiguous merge conflicts.
>
> **Usage:** `/enhanced-automated-sprint 7` or `/enhanced-automated-sprint 7 7-1 7-2 --parallel 2`
>
> | Step | What It Does | BMAD Command | Model | Parallel? |
> |------|-------------|--------------|-------|-----------|
> | 1 | Create story from epic | `/bmad-create-story` | Opus | Yes |
> | 2 | Refine story via elicitation | _(auto-apply methods)_ | Opus | Yes |
> | 3 | Validate story (fresh-context BMAD checklist runner) | _(executes `bmad-create-story/checklist.md`)_ | Opus | Yes |
> | 4 | Write TDD E2E tests (red phase) | `/bmad-qa-generate-e2e-tests` | Sonnet | Yes |
> | 5 | Implement code to pass all tests (TDD unit tests written inline by Amelia) | `/bmad-dev-story` | Sonnet | Yes (worktree) |
> | 6 | Merge implementation branch | _(Amelia dev agent)_ | Opus | No (sequential) |
> | 7 | Consolidated code review | `/bmad-code-review` | Opus | Yes |
> | 8 | Fix review action items | _(targeted fixes)_ | Sonnet | Yes (worktree) |
> | 9 | Merge fix branch + auto-commit (incl. submodules) | _(Amelia dev agent)_ | Opus | No (sequential) |
> | 10 | Update sprint status | `/bmad-sprint-status` | Coordinator | No (sequential) |

Run the full BMAD pipeline for **multiple stories** in an epic using task-based tracking and focused agents.

## Configuration

This skill uses BMAD config variables from `{project-root}/_bmad/bmm/config.yaml`:

| Variable | Source | Used For |
|----------|--------|----------|
| `{project-root}` | runtime | All file path resolution |
| `{project_name}` | config.yaml | Project identification |
| `{output_folder}` | config.yaml | Base output directory for all artifacts |
| `{planning_artifacts}` | config.yaml | Epic files, PRDs, story specs |
| `{implementation_artifacts}` | config.yaml | Sprint status, test reports, trace reports |
| `{project_knowledge}` | config.yaml | Project documentation directory |
| `{user_name}` | config.yaml | Agent greetings and communication |
| `{user_skill_level}` | config.yaml | Agent communication complexity |
| `{communication_language}` | config.yaml | Agent output language |
| `{document_output_language}` | config.yaml | Written artifact language |

### Project-Specific Verification Commands

The pipeline runs verification checks at multiple steps. Configure these for your project's tech stack:

```yaml
# CUSTOMIZE THESE for your project:
test_command: "npx jest"                    # or: pytest, go test ./..., cargo test
test_list_command: "npx jest --listTests | wc -l"  # for test count regression check
typecheck_command: "npx tsc --noEmit"       # or: mypy, go vet, skip if not applicable
build_command: "npm run build"              # or: cargo build, go build, make
lint_command: "npm run lint"                # optional, add to verification if present
```

The coordinator reads these from the project's `CLAUDE.md` or `package.json` scripts. If not found, fall back to the defaults above.

### Agent Environment Block

<env-block CRITICAL="TRUE">
The coordinator MUST include this resolved context block at the START of **every** agent prompt. This is environment configuration, NOT conversation history — Rule #2 does not apply to it.

The coordinator resolves ALL variables from Phase 0 config and runtime discovery before inserting into prompts. Referenced as `${BMAD_ENV_BLOCK}` in agent spawn templates below.

```
## BMAD Environment
- project_root: {project-root}
- project_name: {project_name}
- output_folder: {output_folder}
- planning_artifacts: {planning_artifacts}
- implementation_artifacts: {implementation_artifacts}
- project_knowledge: {project_knowledge}
- user_name: {user_name}
- user_skill_level: {user_skill_level}
- communication_language: {communication_language}
- document_output_language: {document_output_language}

## Verification Commands
- test_command: ${test_command}
- test_list_command: ${test_list_command}
- typecheck_command: ${typecheck_command}
- build_command: ${build_command}
- lint_command: ${lint_command}

## Pipeline Context
- epic_id: ${EPIC_ID}
- working_branch: ${WORKING_BRANCH}
- skill_architecture: ${SKILL_ARCH}
- epic_context_path: ${EPIC_CONTEXT_PATH}
- deferred_decisions_path: ${DEFERRED_DECISIONS_PATH}
```

The coordinator expands `${BMAD_ENV_BLOCK}` to the fully resolved block above at spawn time. Every agent receives the same environment. No variable is withheld.
</env-block>

## Codebase Anti-Leak Block (HARD CONSTRAINT)

<anti-leak CRITICAL="TRUE">
This fork is personal; the user runs BMAD across many projects where the BMAD planning surface is internal-only. Any code, file name, identifier, comment, or main-repo commit message that references BMAD artifacts is a leak. The block below is static text (no variables to substitute) and is referenced as `${ANTI_LEAK_BLOCK}` in agent spawn templates. Phase 0 resolves it once; Steps 5, 6, 8, and 9 receive it immediately after `${BMAD_ENV_BLOCK}` in their prompts.

```
## Codebase Anti-Leak Rules (HARD CONSTRAINT — no opt-out)

These rules are non-negotiable. Apply them to every code surface and every main-repo commit message you produce.

### Rule 1 — Code surfaces (file names, class/function/variable names, route paths, enum values, log messages, inline comments, test names, fixture data)
- NEVER reference story IDs (e.g., "5-1", "${SID}"), story titles, AC numbers, epic IDs, epic titles.
- NEVER include the literal string "BMAD" or any BMAD artifact path/filename.
- Tests describe behavior in user/system terms, not in story-ID or AC-number terms.

### Rule 2 — Main repo commit messages
- NEVER mention BMAD, story IDs, ACs, epics, or sprint runs.
- Describe the change in conventional-commits style — user-facing or technical-purpose terms only.
- Generate the message from `git diff --staged`, NOT from story metadata.

### Rule 3 — Submodule commit messages (EXEMPT)
- BMAD / story / AC references ARE ALLOWED inside private submodules. The user's docs submodule is private; BMAD context belongs there.

### Rule 4 — Internal artifact files (EXEMPT)
- Story files, sprint-status.yaml, the deferred-decisions log, and the epic-context cache all live under `_bmad-output/` (gitignored by convention). They CAN reference BMAD freely. The leak boundary is *checked-in code in the public/main repo*, not BMAD's own output folder.

### Self-check rule
Before saving any code line or main-repo commit message, ask: "If this repo went public tomorrow, would any line I'm writing leak internal planning?" If yes, rewrite.
```
</anti-leak>

## Deferred Decisions Log Format

<deferred-log CRITICAL="TRUE">
The deferred-decisions log is the trust mechanism that makes unattended mode safe — every judgment call gets a paper trail. Path is resolved in Phase 0 as `${DEFERRED_DECISIONS_PATH}` = `{implementation_artifacts}/sprint-epic-${EPIC_ID}-deferred-decisions.md` and is included in `${BMAD_ENV_BLOCK}`. Entries are appended (never rewritten). An empty file is itself a useful signal: nothing was deferred.

### File header (created at Phase 0 if file does not exist; appended-to if it does)

```markdown
# Sprint Deferred Decisions — Epic ${EPIC_ID}
Sprint started: {ISO timestamp}
```

### Entry schema (append on every judgment call)

```markdown
## ${ISO timestamp} | Story ${SID} | Step ${N} (${step_name}) | confidence: ${high|medium|low}
**Question that would have been asked:** {original prompt text}
**Decision made:** {what the agent chose}
**Rationale:** {1–3 sentences — why this was the rational choice given the context}
**Files affected:** {paths if applicable}
**Needs human review:** {yes|no — set yes for medium/low confidence or anything irreversible}
---
```

### Helper instruction block (referenced as `${DEFERRED_LOG_INSTRUCTION_BLOCK}`)

```
## Deferred Decisions Logging
When a decision was made in lieu of asking the user, append an entry to `${DEFERRED_DECISIONS_PATH}` using the schema defined in the coordinator skill (timestamp, story ID, step, confidence, original question, decision, rationale, files affected, needs_human_review). Set `needs_human_review: yes` for medium/low confidence or any irreversible action.
```

This block is included in agent prompts that have decision-point logic (Phase 0 plan log, Step 1 post-create, Step 3 FAIL handling, Step 7 picker, Size M+ warning, failure handling).
</deferred-log>

## Input Format

```
$ARGUMENTS = <EPIC_ID> [STORY_IDS...] [--parallel N] [--skip-elicitation] [--auto-fix]
```

**Examples:**
- `/enhanced-automated-sprint 5` — All `ready-for-dev` + `backlog` stories in Epic 5
- `/enhanced-automated-sprint 5 5-1 5-2` — Only stories 5-1 and 5-2
- `/enhanced-automated-sprint 5 --parallel 2` — Epic 5, run up to 2 stories in parallel
- `/enhanced-automated-sprint 5 5-1 --skip-elicitation` — Skip Step 2 for speed

**Defaults:** `--parallel 1` (sequential), elicitation ON. Unattended mode and auto-fix-Critical-and-High are now ALWAYS ON (see Decision Points below).

> **DEPRECATED:** `--auto-fix` is now the default and has no effect. The flag is accepted as a no-op for backward compatibility with saved invocations, but documented as deprecated. Auto-fix-Critical-and-High behavior is on for every run.

**Story status mapping:** BMAD 6.4 uses `ready-for-dev` as the primary status. The legacy `drafted` status is auto-mapped to `ready-for-dev` for backward compatibility. The coordinator accepts both.

**E2E tests:** Step 4 (E2E TDD) is the sole TDD step. It is blocked by Step 3 (validation) and feeds Step 5 (implementation). Unit tests are written by Amelia inside Step 5 in Kent-Beck-style red-green-refactor — BMAD 6.3+ deliberately removed the standalone unit-TDD skill when Quinn QA was consolidated into Amelia.

**Optimization:** Worktree isolation is decided at spawn time based on **actual concurrency**, not just the `--parallel` flag:
- If `--parallel 1`: Steps 5/8 run directly on the working branch WITHOUT worktree isolation (no merge steps 6/9 needed).
- If `--parallel >= 2` but only ONE story is actually at Step 5/8 in this wave: skip worktree, run directly. No point paying worktree + merge overhead for a single concurrent implementation.
- If `--parallel >= 2` AND multiple stories reach Step 5/8 in the same wave: use `isolation: "worktree"` for each, then sequential merges via Steps 6/9.

## Phase 0: Discovery & Planning

<rules CRITICAL="TRUE">
Before ANY pipeline work begins, the coordinator MUST:

1. **Load BMAD config** — read `{project-root}/_bmad/bmm/config.yaml` and resolve ALL variables: `{project_name}`, `{output_folder}`, `{planning_artifacts}`, `{implementation_artifacts}`, `{project_knowledge}`, `{user_name}`, `{user_skill_level}`, `{communication_language}`, `{document_output_language}`
2. **Resolve verification commands** — read `CLAUDE.md` or `package.json` scripts to determine `${test_command}`, `${test_list_command}`, `${typecheck_command}`, `${build_command}`, `${lint_command}`. Fall back to defaults if not found.
3. **Determine working branch** — run `git branch --show-current` and store as `${WORKING_BRANCH}`
4. **Detect skill architecture** — check if `.claude/skills/` directory exists. If yes, set `${SKILL_ARCH}` to `skills`. If only `.claude/commands/` exists, set to `commands`. Store for agent spawn templates (affects skill invocation paths). Probe skill availability by spawning a lightweight agent that attempts `/bmad-help` — if it fails, switch all templates to inline-workflow mode (load workflow YAML directly instead of invoking `/bmad-*` skills).
5. **Resolve `${ANTI_LEAK_BLOCK}`** — copy the static text from the "Codebase Anti-Leak Block (HARD CONSTRAINT)" section above into a single string. No variables to substitute. Store for injection into Steps 5, 6, 8, 9 prompts.
6. **Build `${BMAD_ENV_BLOCK}`** — expand the Agent Environment Block template with all resolved values (including `${EPIC_CONTEXT_PATH}` and `${DEFERRED_DECISIONS_PATH}` once resolved in steps 9–10 below). This block is injected into every agent prompt for the rest of the pipeline.
7. **Parse `$ARGUMENTS`** — extract EPIC_ID, optional STORY_IDS, and flags. (`--auto-fix` is a no-op; record but ignore.)
8. **Read sprint-status.yaml** at `{implementation_artifacts}/sprint-status.yaml`
9. **Compile or reuse epic context.**
   1. Look for cached file: `{implementation_artifacts}/epic-${EPIC_ID}-context.md`. Validity criteria: file exists, non-empty, starts with `# Epic ${EPIC_ID} Context:`, AND no file in `{planning_artifacts}` is newer (`mtime` comparison).
   2. If valid: store its path as `${EPIC_CONTEXT_PATH}` and proceed.
   3. If missing or stale: spawn a single sub-agent (`subagent_type: general-purpose`, `model: sonnet`) whose prompt instructs it to read `{project-root}/_bmad/bmm/skills/bmad-quick-dev/compile-epic-context.md` and execute it against `${EPIC_ID}`, writing output to `{implementation_artifacts}/epic-${EPIC_ID}-context.md`. Do NOT inline the prompt — reference the BMAD file by path. Capture the path as `${EPIC_CONTEXT_PATH}`.
   4. Add `${EPIC_CONTEXT_PATH}` to `${BMAD_ENV_BLOCK}` so every downstream agent receives it.
10. **Initialize deferred-decisions log.**
   1. Resolve `${DEFERRED_DECISIONS_PATH}` = `{implementation_artifacts}/sprint-epic-${EPIC_ID}-deferred-decisions.md`.
   2. If file does not exist: create with header `# Sprint Deferred Decisions — Epic ${EPIC_ID}\n\nSprint started: {ISO timestamp}\n\n`.
   3. If file already exists (prior run for this epic): append a separator + a new sprint-run header (do NOT overwrite).
   4. Add `${DEFERRED_DECISIONS_PATH}` to `${BMAD_ENV_BLOCK}` so every downstream agent can append entries.
11. **Identify target stories:**
   - If STORY_IDS provided: use exactly those
   - If only EPIC_ID: collect all stories with status `ready-for-dev`, `backlog`, or `drafted` (legacy — auto-mapped to `ready-for-dev`). Skip `done`, `in-progress`.
12. **Read the epic file** at `{planning_artifacts}/epic-${EPIC_ID}.md` to understand story dependencies and ordering
13. **Determine story execution order:**
   - Stories with no inter-story dependencies can run in parallel (up to `--parallel N`)
   - Stories that depend on other stories in the batch must run after their dependency completes
   - Default: sequential in story number order
14. **Size check:** If any story is Size M or larger, append a `confidence: medium, needs_human_review: yes, suggested action: 'consider decomposing'` entry to `${DEFERRED_DECISIONS_PATH}` and proceed (do NOT block — see Decision Points). The user reviews the log post-sprint.
15. **Create the task list** using TaskCreate (see Task Structure below)
16. **Log the plan and proceed (no approval pause).** Print the plan to stdout for transcript visibility, then append a "Sprint plan committed" entry to `${DEFERRED_DECISIONS_PATH}` with `confidence: high, needs_human_review: no`. Proceed directly into the wave-loop without waiting for user input.
</rules>

## Task Structure

For each story, create tasks using TaskCreate, then set dependencies via TaskUpdate (`addBlockedBy`). The coordinator creates ALL tasks upfront, then wires up `blockedBy` relationships, then works through them respecting dependencies.

### Task Naming Convention

Tasks use the format: `[STORY_ID] Step N: <step-name>`

This ensures unique task names across stories and clear identification.

### Per-Story Tasks (created for EACH story)

For story `${SID}`:

| Task Subject | ActiveForm | Blocked By |
|---|---|---|
| `[${SID}] Step 1: Create story` | `Creating story ${SID}` | — * |
| `[${SID}] Step 2: Advanced elicitation` | `Running elicitation on ${SID}` | `[${SID}] Step 1: Create story` |
| `[${SID}] Step 3: Validate story` | `Validating story ${SID}` | `[${SID}] Step 2: Advanced elicitation` |
| `[${SID}] Step 4: TDD E2E test generation` | `Generating TDD E2E tests for ${SID}` | `[${SID}] Step 3: Validate story` |
| `[${SID}] Step 5: Implementation` | `Implementing story ${SID}` | `[${SID}] Step 4: TDD E2E test generation` |
| `[${SID}] Step 6: Merge implementation` | `Merging ${SID} implementation to main branch` | `[${SID}] Step 5: Implementation` |
| `[${SID}] Step 7: Consolidated code review` | `Reviewing code for ${SID}` | `[${SID}] Step 6: Merge implementation` |
| `[${SID}] Step 8: Fix action items` | `Fixing review items for ${SID}` | `[${SID}] Step 7: Consolidated code review` |
| `[${SID}] Step 9: Merge fixes` | `Merging ${SID} review fixes to main branch` | `[${SID}] Step 8: Fix action items` |
| `[${SID}] Step 10: Update sprint status` | `Updating sprint status for ${SID}` | `[${SID}] Step 9: Merge fixes` |

**\*** Coordinator sets Step 1 `blockedBy` dynamically: no blocker in parallel mode, previous story's Step 10 in sequential mode (`--parallel 1`), or inter-story dependency's Step 10 if epic defines one.

If `--skip-elicitation`: ALWAYS create Step 2 in the task graph (keeps the dependency chain intact), but mark it as `completed` immediately at creation time. This avoids conditional task graph construction — Step 3 still blocks on Step 2, which is already done.

### Cross-Story Dependencies

- **Sequential mode** (`--parallel 1`): Story B's Step 1 is blocked by Story A's Step 10
- **Parallel mode** (`--parallel N`): No cross-story `blockedBy` for independent stories — the **coordinator** enforces parallelism limits and merge gates (Steps 6, 9) at spawn time, NOT via task dependencies. This keeps the task graph simple and avoids false blocking.
  - Exception: Stories WITH inter-story dependencies (noted in epic file) DO get `blockedBy` on their dependency's Step 10.
- **Worktree isolation** (Steps 5, 8): These steps run in git worktrees (`isolation: "worktree"`), so they CAN run in parallel across stories. Each agent gets its own repo copy — no file conflicts during implementation.
- **Merge gates** (Steps 6, 9): After worktree work completes, the **BMAD Dev Agent (Amelia — Senior Software Engineer)** integrates the worktree branch back to the working branch. Merges run SEQUENTIALLY (one at a time) to avoid merge race conditions. Amelia resolves conflicts with senior-level judgment, verifies all tests pass post-merge, and speaks in file paths and AC IDs — no fluff. Step 9 additionally performs the per-story auto-commit sequence (see Step 9 template).

### Epic-Level Tasks

| Task Subject | ActiveForm | Blocked By |
|---|---|---|
| `[Epic ${EPIC_ID}] Cross-story integration check` | `Running cross-story integration verification` | All stories' Step 10 |
| `[Epic ${EPIC_ID}] Sprint summary` | `Generating sprint summary` | `[Epic ${EPIC_ID}] Cross-story integration check` |

**Cross-story integration check** runs AFTER all stories are individually complete. It verifies that stories don't break each other when combined:
1. Run: `${test_command}` — full test suite (catches cross-story conflicts like duplicate routes, naming collisions)
2. Run: `${typecheck_command}` — type check (catches cross-story type conflicts)
3. Run: `${build_command}` — full build (catches cross-story import/bundling issues)
4. If any check fails: log a `confidence: low, needs_human_review: yes` entry to `${DEFERRED_DECISIONS_PATH}` identifying the failing tests/errors and the stories whose files are involved, then proceed to sprint summary (do NOT block; the log surfaces it for the user).
5. If all pass: mark as completed, proceed to sprint summary

## Execution Engine: Parallel Story Processing

<parallel-execution CRITICAL="TRUE">
The coordinator runs a **wave-based execution loop**. Each iteration:

1. **Call TaskList** — get all tasks and their statuses
2. **Identify ALL unblocked tasks** — tasks where every `blockedBy` dependency is `completed`
3. **Group unblocked tasks by concurrency rules:**
   - Steps 1, 2, 3 (story creation/elicitation/validation): **PARALLEL** — no shared files
   - Step 4 (TDD E2E): **PARALLEL** — safe because E2E test files are story-scoped. Each agent writes only to its own story's E2E test files. If stories share a test file, fall back to SEQUENTIAL for Step 4.
   - Step 5 (implementation): **PARALLEL in worktrees** — `isolation: "worktree"` gives each agent its own repo copy
   - Steps 6, 9 (merges): **SEQUENTIAL** — merge one worktree branch at a time to avoid race conditions; Step 9 also performs auto-commit
   - Step 7 (consolidated review): **PARALLEL** — read-only analysis. BMAD 6.4 runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally within a single `/bmad-code-review` invocation.
   - Step 8 (fixes): **PARALLEL in worktrees** — same worktree isolation as Step 5
   - Step 10: **COORDINATOR-SEQUENTIAL** — delegates to `/bmad-sprint-status` one story at a time. Two concurrent writes to the same YAML file = data loss.
4. **Spawn agents for ALL parallelizable unblocked tasks in a SINGLE message** — this is how Claude Code runs agents concurrently. Multiple Task tool calls in one response = true parallelism.
5. **Wait for all spawned agents to complete**
6. **Mark completed tasks, report results, loop back to step 1**

### Parallelism Example

Given stories A-1 and A-2 with `--parallel 2` and no inter-story dependencies:

```
Wave 1:  [A-1] Step 1 + [A-2] Step 1         parallel (story creation)
Wave 2:  [A-1] Step 2 + [A-2] Step 2         parallel (elicitation)
Wave 3:  [A-1] Step 3 + [A-2] Step 3         parallel (validation)
Wave 4:  [A-1] Step 4 + [A-2] Step 4         parallel (E2E TDD)
Wave 5:  [A-1] Step 5 + [A-2] Step 5         parallel IN WORKTREES
Wave 6:  [A-1] Step 6                         SEQUENTIAL merge
Wave 7:  [A-2] Step 6                         SEQUENTIAL merge
Wave 8:  [A-1] Step 7 + [A-2] Step 7         parallel (consolidated review)
Wave 9:  [A-1] Step 8 + [A-2] Step 8         parallel IN WORKTREES (fixes)
Wave 10: [A-1] Step 9                         SEQUENTIAL merge + auto-commit
Wave 11: [A-2] Step 9                         SEQUENTIAL merge + auto-commit
Wave 12: [A-1] Step 10, then [A-2] Step 10   COORDINATOR-SEQUENTIAL
```

**Speedup:** 12 waves vs ~18+ sequential steps. BMAD 6.4's consolidated review (Blind Hunter + Edge Case Hunter + Acceptance Auditor in a single invocation) replaces the 3 separate review agents from prior versions, reducing review from 3 parallel agents to 1 without losing coverage. Implementation (the longest step) runs concurrently across stories.

### How to Spawn Parallel Agents

**CRITICAL:** To run agents in parallel, you MUST include multiple Task tool calls in a SINGLE response message. Example:

```
Response contains:
  Task tool call 1: "[A-1] Step 1: Create story"
  Task tool call 2: "[A-2] Step 1: Create story"
```

Both agents launch concurrently. You receive both results before your next turn.

**DO NOT** spawn one agent, wait for it, then spawn the next — that is sequential, not parallel.

### Worktree Isolation (Steps 5, 8)

Steps 5 and 8 run with `isolation: "worktree"` on the Task tool. This gives each agent its own git worktree — a full copy of the repo on its own branch. Multiple stories implement concurrently without file conflicts.

The worktree agent's branch and path are returned in the Task result. The coordinator passes this info to the merge step.

### Sequential Merge Gates (Steps 6, 9)

These are the ONLY serialization points in the pipeline. Merges run one at a time to prevent race conditions:

| Step | What | Who |
|------|------|-----|
| Step 6: Merge implementation | Merge worktree branch from Step 5 into working branch (NO auto-commit downstream) | **BMAD Dev Agent (Amelia)** — Opus |
| Step 9: Merge fixes + auto-commit | Merge worktree branch from Step 8 into working branch, then auto-commit (submodule-first, then main repo, anti-leak applied) | **BMAD Dev Agent (Amelia)** — Opus |

All other steps parallelize freely because they either:
- Write to story-specific files (Steps 1, 2, 4)
- Run in isolated worktrees (Steps 5, 8)
- Are read-only analysis (Steps 3, 7)

Step 10 delegates to `/bmad-sprint-status` and runs sequentially (shared `sprint-status.yaml` file).
</parallel-execution>

## Execution Rules

<rules CRITICAL="TRUE">
1. **Act as COORDINATOR** — delegate all work via Task tool agents, do NOT execute pipeline steps yourself
2. **One agent per step** — each step spawns a focused Task agent. Do NOT pass full conversation history. DO pass `${BMAD_ENV_BLOCK}` to every agent — environment variables are configuration, not history. For Steps 5, 6, 8, 9 ALSO prepend `${ANTI_LEAK_BLOCK}` immediately after `${BMAD_ENV_BLOCK}`.
3. **PARALLEL by default** — when multiple tasks are unblocked AND parallelizable (see Sequential Gate Rules above), spawn them ALL in a single message. This is the core performance advantage of the enhanced pipeline.
4. **TaskUpdate before and after** — mark task `in_progress` BEFORE spawning the agent, mark `completed` AFTER agent succeeds
5. **TaskList after each wave** — check what's unblocked next
6. **Failure stops the STORY, not the sprint** — on step failure: log to `${DEFERRED_DECISIONS_PATH}` and retry once with the same agent. On second failure, mark the story `blocked`, log a follow-up entry, and continue with other independent stories.
7. **Context budget per agent:** Each agent should read at most 5-8 files. If a step needs more context, break it into sub-agents.
8. **Steps 8 + 9 are conditional** — only create a fix agent if Step 7 produced action items. If Step 7 (consolidated review) reports no action items, mark BOTH 8 AND 9 as completed immediately and proceed to Step 10. If Step 7 produced ONLY Medium/Low items (which are deferred to the log), also mark 8 + 9 completed and proceed to Step 10.
8a. **Tasks/Subtasks validation gate** — after Step 5 completes, the coordinator MUST check the agent's return for "Tasks/Subtasks completion". If the agent reports incomplete tasks or does NOT confirm story file was updated, the coordinator logs a `confidence: low, needs_human_review: yes` entry to `${DEFERRED_DECISIONS_PATH}` and proceeds (does not pause). The story file's `## Tasks / Subtasks` section is the source of truth for implementation completeness — test results alone are NOT sufficient.
9. **Step 10 uses BMAD** — delegate to `/bmad-sprint-status` to update sprint-status.yaml, one story at a time (sequential)
10. **Progress checkpoints** — after every wave, output a progress summary to the user
11. **If context feels heavy** — after completing a full story's pipeline, output a handoff summary and suggest the user refresh the session if more stories remain
12. **Skill invocation** — BMAD 6.4 uses `.claude/skills/` with `SKILL.md` entry points. When invoking `/bmad-*` skills inside agents, the coordinator should verify skill paths match the detected `${SKILL_ARCH}` from Phase 0. If skills are in `.claude/skills/`, agents invoke them as `/bmad-*` (unchanged command name). If the Skill tool is unavailable inside Task agents, fall back to inline-workflow mode.
</rules>

## Agent Spawn Templates

### Focused Agent Pattern

Each agent gets a **minimal, focused prompt** plus the full `${BMAD_ENV_BLOCK}` — only step-specific context varies, environment is always included. Steps that produce checked-in code or main-repo commit text (Steps 5, 6, 8, 9) ALSO receive `${ANTI_LEAK_BLOCK}` immediately after `${BMAD_ENV_BLOCK}`.

**NOTE:** Templates below are pseudo-code showing the Task tool parameters. The coordinator translates these to actual Task tool calls with JSON parameters. All named parameters (`description`, `subagent_type`, `model`, `isolation`, `prompt`) are real Task tool parameters. The `<-` inline comments are documentation only — do not include them in actual tool calls.

**SKILL INVOCATION WARNING:** Steps 1, 4, 5, and 7 invoke `/bmad-*` skills or workflows inside Task agents. Step 3 reads and executes a BMAD checklist file in fresh context (no skill invocation). If the Skill tool is not available inside Task agents, the coordinator MUST use a fallback: instead of `Execute: /bmad-create-story ${SID}`, load the skill's workflow YAML directly and pass its instructions inline in the prompt. The coordinator should test skill availability in Phase 0 by spawning a lightweight probe agent that attempts `/bmad-help` — if it fails, switch all templates to inline-workflow mode. In BMAD 6.4, skills live under `.claude/skills/` with `SKILL.md` entry points.

#### Step 1: Create Story
```
Task tool:
  description: "[${SID}] Create story"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    Run the BMAD create-story workflow for story ${SID}.
    Execute: /bmad-create-story ${SID}

    Pre-compiled epic context: ${EPIC_CONTEXT_PATH} — load this BEFORE the epic file; it is the distilled, scope-aggressive view of the epic.
    Epic file: {planning_artifacts}/epic-${EPIC_ID}.md
    Sprint status: {implementation_artifacts}/sprint-status.yaml

    CRITICAL: The "## Tasks / Subtasks" section in the story file MUST be populated with real,
    actionable implementation tasks derived from the Acceptance Criteria — NOT left as template
    placeholders like "Task 1 (AC: #)". Each task must:
    - Map to one or more specific ACs (e.g., "- [ ] Set up Express server with health endpoint (AC: 1, 2)")
    - Be broken into subtasks where the task involves multiple discrete actions
    - Use checkbox format: "- [ ] Task description (AC: #)"

    After the create-story workflow completes, VERIFY the Tasks/Subtasks section contains real tasks.
    If it still has template placeholders, rewrite the section based on the ACs before returning.

    Return to coordinator:
    - Story file path created
    - AC count and 1-line summary each
    - Task breakdown count (MUST be > 0 with real task descriptions, not placeholders)
    - Any blockers or questions
```

#### Step 2: Advanced Elicitation (Automated)
```
Task tool:
  description: "[${SID}] Elicitation"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    You are enhancing story ${SID} via advanced elicitation. This is FULLY AUTOMATED.

    1. Read the story file at: ${STORY_FILE_PATH}
    2. Read methods CSV at: {project-root}/_bmad/core/workflows/advanced-elicitation/methods.csv
    3. Auto-select the 3 methods most relevant to this story's context
    4. Apply each method in sequence to enhance the story
    5. Save the enhanced story file (overwrite at ${STORY_FILE_PATH})
    6. Report ONLY THE DELTA — what changed, section by section

    CRITICAL: After elicitation, verify the "## Tasks / Subtasks" section still contains real,
    actionable tasks with checkbox format (- [ ] Task description (AC: #)). If elicitation
    accidentally removed or degraded the tasks section, restore it with properly mapped tasks.

    Return to coordinator: section-by-section delta summary. Do NOT return the full story file.
```

#### Step 3: Validate Story (Fresh-Context BMAD Checklist Runner)
```
Task tool:
  description: "[${SID}] Validate (BMAD checklist runner)"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    You are an independent quality validator running in a FRESH CONTEXT. Your job is to execute
    BMAD's authoritative story-validation checklist against story ${SID}.

    1. Read and follow the checklist at:
       {project-root}/_bmad/bmm/skills/bmad-create-story/checklist.md
       This file is BMAD-grade — an 8-step systematic re-analysis explicitly designed for
       fresh-context invocation. Treat it as the source of truth for what "validated" means.
    2. Inputs to validate:
       - Story file: ${STORY_FILE_PATH}
       - Epic file: {planning_artifacts}/epic-${EPIC_ID}.md
       - Pre-compiled epic context: ${EPIC_CONTEXT_PATH} (load alongside the epic file)
    3. SKIP the checklist's interactive elicitation menu. This run is automated.
    4. Auto-apply Critical-tier findings directly to the story file at ${STORY_FILE_PATH}.
       Do NOT auto-apply Enhancement-tier or Optimization-tier findings — log those as
       findings only.
    5. For every Enhancement / Optimization finding (and for any Critical fix you applied),
       append an entry to ${DEFERRED_DECISIONS_PATH} per the documented schema (story ${SID},
       step "Step 3 Validate", appropriate confidence level, needs_human_review yes for
       medium/low confidence).

    Return to coordinator (return contract):
    - verdict: PASS | FAIL | action-items
    - critical_count: <int>
    - enhancement_count: <int>
    - optimization_count: <int>
    - changes_applied_to_story_file: [list of section-level edits]
    - findings_logged_to_deferred_decisions: [list of entry summaries]
```

#### Step 4: TDD E2E Test Generation
```
Task tool:
  description: "[${SID}] TDD E2E tests"
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    ${BMAD_ENV_BLOCK}

    Generate TDD E2E tests for story ${SID} in red-phase mode. These tests should FAIL
    before implementation and PASS after.
    Execute: /bmad-qa-generate-e2e-tests ${SID}

    Story file: ${STORY_FILE_PATH}

    Scope your E2E tests to the acceptance criteria in the story file. Each AC should have
    at least one E2E test that exercises the full user workflow end-to-end.

    Save E2E test report to: {implementation_artifacts}/${SID}-e2e-tdd-test-report.md

    Return to coordinator:
    - E2E test file paths created
    - E2E test count
    - AC coverage (which ACs are covered by which E2E tests)
    - Red phase confirmation (all E2E tests fail as expected)
    - Report file path: {implementation_artifacts}/${SID}-e2e-tdd-test-report.md
```

#### Step 5: Implementation (Worktree Isolated)
```
Task tool:
  description: "[${SID}] Implement"
  subagent_type: general-purpose
  model: sonnet
  isolation: "worktree"          <- agent gets its own repo copy (only when parallel)
  prompt: |
    ${BMAD_ENV_BLOCK}
    ${ANTI_LEAK_BLOCK}

    Implement story ${SID} by following the story file's Tasks/Subtasks section.
    Execute: /bmad-dev-story ${SID} yolo

    Pre-compiled epic context: ${EPIC_CONTEXT_PATH} — load this BEFORE the epic file; it is the distilled, scope-aggressive view of the epic.
    Story file: ${STORY_FILE_PATH}
    E2E test files: ${E2E_TEST_FILE_PATHS}

    UNIT TESTS — KENT-BECK TDD INSIDE THIS STEP:
    BMAD 6.3+ removed the standalone unit-TDD generation skill when Quinn QA was consolidated
    into Amelia. Amelia's identity now explicitly includes "Disciplined in Kent Beck's TDD".
    Write unit tests TDD-style as you implement: red phase first (failing test that captures the
    behavior), green phase (minimum implementation), refactor. Do NOT skip the red phase.

    CRITICAL — STORY FILE TASK TRACKING:
    The story file at ${STORY_FILE_PATH} contains a "## Tasks / Subtasks" section with checkboxes.
    You MUST follow the dev-story workflow's task-driven implementation loop:
    1. Find the first incomplete task (unchecked [ ]) in "Tasks / Subtasks"
    2. Implement that specific task (use existing E2E TDD tests from ${E2E_TEST_FILE_PATHS} as
       acceptance verification; write Kent-Beck-style unit tests for the internals)
    3. When the task's tests pass AND implementation matches the task spec, mark it [x] in the story file
    4. Update the story file's "Dev Agent Record" and "File List" sections
    5. Loop back to step 1 until ALL tasks/subtasks are marked [x]

    ALL TESTS MUST PASS: Both the unit tests you write inline AND the E2E tests
    (${E2E_TEST_FILE_PATHS}) must pass.

    APPLY ${ANTI_LEAK_BLOCK} to every file name, identifier, comment, log message, test name,
    and fixture you produce. Story IDs, AC numbers, epic refs, and the literal "BMAD" must NEVER
    appear in checked-in code surfaces.

    After ALL tasks are complete, save the story file with:
    - All Tasks/Subtasks checkboxes marked [x]
    - Updated File List with all changed/created files
    - Dev Agent Record with implementation notes
    - Status updated to "review"

    Return to coordinator:
    - Files changed/created
    - Unit test results (count passing, count failing)
    - E2E test results (count passing, count failing)
    - Typecheck status
    - Build status
    - Key implementation decisions
    - Tasks/Subtasks completion: [count completed]/[total count] — ALL must be [x]
    - Story file updated: YES/NO (MUST be YES)

    IMPORTANT: Your changes are in a worktree branch. Do NOT merge — the coordinator handles merging.
```

**Coordinator note:** The Task result will include the worktree branch name and path. Save these for Step 6.

#### Step 6: Merge Implementation (BMAD Dev Agent — SEQUENTIAL)
```
Task tool:
  description: "[${SID}] Dev merge"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}
    ${ANTI_LEAK_BLOCK}

    You are Amelia, the BMAD Developer Agent — a Senior Software Engineer.
    Your identity: Execute with strict adherence to story details and team standards.
    Your communication style: Ultra-succinct. Speak in file paths and AC IDs — every statement citable. No fluff, all precision.
    Your principle: All existing and new tests must pass 100%.

    ## Your Role
    You are the quality gate between isolated implementation and the shared codebase.
    You merge with the judgment of a senior engineer — not blindly.

    NOTE: Step 6 merges the implementation worktree into the working branch but does NOT
    auto-commit downstream — auto-commit happens after the full review-fix cycle in Step 9.
    The merge commit produced by `git merge --no-ff` is the only commit in this step.

    ## Context
    - Worktree branch: ${WORKTREE_BRANCH} (from Step 5 result)
    - Target branch: ${WORKING_BRANCH}
    - Story: ${SID}
    - Story file: ${STORY_FILE_PATH}

    ## Merge Protocol

    1. **Pre-merge setup:**
       - Run: git checkout ${WORKING_BRANCH}
       - Verify: git branch --show-current (MUST be on target branch before merge)

    2. **Pre-merge review:**
       - Run: git log ${WORKING_BRANCH}..${WORKTREE_BRANCH} --oneline
       - Understand what the implementation branch changed
       - Run: git diff ${WORKING_BRANCH}...${WORKTREE_BRANCH} --stat
       - Identify files touched and potential conflict areas

    3. **Merge:**
       - Generate the merge commit message using ${ANTI_LEAK_BLOCK} (no story ID, no "BMAD",
         no AC numbers, no epic refs — describe the change in conventional-commits style from
         `git diff --staged` semantics).
       - Run: git merge ${WORKTREE_BRANCH} --no-ff -m "${anti_leak_merge_message}"
       - If clean merge: proceed to verification
       - If conflicts: resolve them with senior judgment (see sub-step 4 below — Conflict Resolution)

    4. **Conflict Resolution (if needed):**
       - Read BOTH versions of conflicting files fully
       - Read the story file to understand the INTENT of the changes
       - Resolve by preserving both stories' functionality — never silently drop one side
       - **Ambiguous merge conflicts are the ONE hard pause point in unattended mode** — irreversible-state risk. If a conflict is ambiguous (unclear which side is correct), STOP and report to coordinator. The coordinator surfaces the conflict to the user immediately, blocks this story only, and continues other independent stories.
       - After resolving: git add <resolved files> && git commit -m "${anti_leak_resolution_message}"

    5. **Post-merge verification:**
       - Pre-merge test count: run `${test_list_command}` BEFORE the merge (capture in step 1)
       - Run: ${test_command} (ALL tests must pass — not just this story's tests)
       - Post-merge test count: run `${test_list_command}` AFTER merge
       - **Test count regression check:** post-merge count MUST be >= pre-merge count. If tests were deleted by the merge, STOP and report — this is a merge conflict resolution error.
       - Run: ${typecheck_command} (must be clean)
       - Run: ${build_command} (must succeed)
       - If any check fails: diagnose, fix, commit the fix, re-verify

    6. **Cleanup:**
       - Check if worktree still exists: git worktree list
       - If Task tool auto-cleaned the worktree: skip removal
       - If worktree still exists: git worktree remove ${WORKTREE_PATH} && git branch -d ${WORKTREE_BRANCH}

    ## Return to coordinator
    - Merge result: clean / conflicts resolved / BLOCKED (ambiguous conflict)
    - Conflicts: [list files if any, with resolution summary]
    - Post-merge tests: [count] passing (pre-merge: [count], delta: +[N])
    - Test count regression: none / REGRESSION DETECTED ([details])
    - Typecheck: clean / [errors]
    - Build: success / failure
    - Files merged: [count]
    - Anti-leak check on commit message: pass / manual_review_needed
```

#### Step 7: Consolidated Code Review
```
Task tool:
  description: "[${SID}] Consolidated review"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    Run the BMAD 6.4 consolidated code review for story ${SID}.
    Execute: /bmad-code-review ${SID} yolo

    Pre-compiled epic context: ${EPIC_CONTEXT_PATH} — load this BEFORE the epic file; it is the distilled, scope-aggressive view of the epic.
    Story file: ${STORY_FILE_PATH}
    Implementation files: ${IMPL_FILE_PATHS}
    Test files: ${TEST_FILE_PATHS}

    BMAD 6.4's code review runs 3 internal review passes:
    1. Blind Hunter — architectural and security review
    2. Edge Case Hunter — method-driven path enumeration for unhandled edge cases
    3. Acceptance Auditor — AC-by-AC verification of implementation completeness

    All three run within a single /bmad-code-review invocation. You do NOT need to
    invoke them separately.

    Return to coordinator:
    - Overall verdict: PASS / PASS WITH ITEMS / FAIL
    - Findings table with source attribution:
      (# | source [blind/edge/acceptance] | severity | category | finding | recommendation)
    - Critical count (by source)
    - Total action item count
    - Edge case findings in JSON format (for Step 8 if fixes needed):
      [{location, trigger_condition, guard_snippet, potential_consequence}, ...]
    - AC verification report from the Acceptance Auditor pass: per-AC verdict
      (AC ID | covered_by_tests | implementation_complete | notes) — surface this prominently
      so it stands in for the dropped AC-trace step.
```

**Coordinator note:** This single step replaces the old Steps 7 (code review), 8 (adversarial review), 8b (edge case hunter), AND 10 (AC trace). BMAD 6.4 runs all three review types internally and the Acceptance Auditor's per-AC verdict supplants the standalone AC-trace step. The coordinator receives unified findings with source attribution and routes them per the Decision Points rules.

#### Step 8: Fix Action Items (Conditional, Worktree Isolated)
```
Task tool:
  description: "[${SID}] Fix review items"
  subagent_type: general-purpose
  model: sonnet
  isolation: "worktree"          <- fixes run in isolated worktree (only when parallel)
  prompt: |
    ${BMAD_ENV_BLOCK}
    ${ANTI_LEAK_BLOCK}

    Fix the following action items from the consolidated code review for story ${SID}.
    The review included findings from Blind Hunter, Edge Case Hunter, and Acceptance Auditor.
    Only Critical and High severity items are routed here; Medium and Low are deferred to the
    decisions log per the unattended defaults.

    Items to fix:
    ${CONSOLIDATED_ACTION_ITEMS}

    Edge case findings (JSON — add guards for critical ones):
    ${EDGE_CASE_FINDINGS}

    Implementation files: ${IMPL_FILE_PATHS}
    Test files: ${TEST_FILE_PATHS}

    APPLY ${ANTI_LEAK_BLOCK} to every code surface you touch — file names, identifiers,
    comments, test names, fixture data. No story IDs, no AC numbers, no "BMAD".

    After fixing:
    1. Run: ${test_command} (all tests must pass)
    2. Run: ${typecheck_command} (must be clean)
    3. Run: ${build_command} (must succeed)
    4. Update the story file's "## Tasks / Subtasks" section:
       - If a "Review Follow-ups (AI)" subsection was added by code review, mark fixed items [x]
       - Ensure ALL original task checkboxes remain [x] (do not regress them)

    Return to coordinator: each fix with before/after, test count, typecheck status, build status, story file Tasks/Subtasks status.
    IMPORTANT: Your changes are in a worktree branch. Do NOT merge — the coordinator handles merging.
```

**Coordinator note:** Save worktree branch/path from result for Step 9. If Step 8 was skipped (no Critical/High action items from Step 7), also skip Step 9.

#### Step 9: Merge Fixes + Auto-Commit (BMAD Dev Agent — SEQUENTIAL)

Same agent template as Step 6 (Amelia, Senior Software Engineer persona) with `${BMAD_ENV_BLOCK}` and `${ANTI_LEAK_BLOCK}` included in the prompt, but with:
- Description: `"[${SID}] Dev merge fixes"`
- Worktree branch/path from Step 8 result
- Merge commit message generated under `${ANTI_LEAK_BLOCK}` (no story ID, no "BMAD", no AC numbers)
- An ADDITIONAL post-merge sub-section: **Step 7 — Auto-commit** (see below). Insert this between the existing post-merge verification (sub-step 5 in Step 6) and cleanup (sub-step 6 in Step 6).

```
## Step 7: Auto-commit (Step 9 only — Step 6 does NOT run this)

This sub-section is appended to Amelia's merge protocol for Step 9. It runs AFTER post-merge
verification passes and BEFORE worktree cleanup.

1. **Detect submodules:**
   - Run: git submodule status
   - For each submodule path in the output, check: cd ${path} && git status --porcelain
   - Build the list of dirty submodules (in submodule order).

2. **For each dirty submodule (in order):**
   - cd ${submodule_path}
   - git add -A
   - git commit -m "${submodule_message}"
   - **submodule_message MAY reference BMAD context** (story ID, AC summary, link to story file
     under _bmad-output/) per Anti-Leak Rule 3. Example:
     `chore: notes for story ${SID} — ${story_title}`
   - Return to main repo working dir (cd back to project_root).
   - Capture the submodule commit SHA.

3. **Main repo commit:**
   - Run: git add -A
     This stages files modified by the implementation + the submodule pointer bumps from step 2.
   - Generate the main-repo commit message:
     - Read: git diff --staged
     - Apply ${ANTI_LEAK_BLOCK} rules verbatim — NO story ID, NO "BMAD", NO AC numbers,
       NO epic references.
     - Produce a conventional-commits format message describing the user-facing or
       technical purpose of the change.
   - Run: git commit -m "${main_message}"
   - Capture the main commit SHA.

4. **Verification:**
   - Run: git status --porcelain
   - MUST be empty after this sequence. If not empty, STOP and report what is still dirty.

5. **Failure handling:**
   - If a commit hook fails: diagnose and fix the underlying issue per existing rules; never
     pass --no-verify. After fixing, re-stage and commit anew.

6. **No push:**
   - NEVER run git push. Auto-commit is local only. The user pushes manually after reviewing
     the deferred-decisions log.

## Step 9 — Additional Return Contract Fields

In addition to the Step 6 return fields, Step 9 MUST return:
- submodule_commit_shas: [array of SHA strings, in submodule order]
- main_commit_sha: <SHA string>
- commit_message_anti_leak_check: pass | fail | manual_review_needed
```

#### Step 10: Update Sprint Status
```
Coordinator delegates to:  /bmad-sprint-status
One story at a time (sequential — shared sprint-status.yaml file).
The coordinator translates Step 9's return contract into the appropriate sprint-status.yaml
updates for story ${SID}.
```

## Step Output Requirements

### Step 6 / 9: BMAD Dev Agent (Amelia) Merge — Output
```
**Step 6 Complete: Amelia Merge — ${SID}**
- Merge result: clean / conflicts resolved / BLOCKED
- Worktree branch: ${WORKTREE_BRANCH} -> ${WORKING_BRANCH}
- Conflicts: [list files + resolution summary, or "None"]
- Post-merge tests: [count] passing (pre-merge: [count], delta: +[N])
- Test count regression: none / REGRESSION DETECTED
- Typecheck: clean / [errors]
- Build: success / failure
- Files merged: [count]
- Anti-leak check on commit message: pass / manual_review_needed
```

For Step 9, additionally:
```
**Step 9 Auto-commit — ${SID}**
- Submodule commits: [list of paths + SHAs, or "None — no dirty submodules"]
- Main repo commit: ${main_commit_sha} — "${main_message}"
- git status --porcelain: empty
- Anti-leak check: pass
```

The coordinator MUST present each step's output as it completes. Do NOT batch outputs.

## Progress Reporting

### After Each Task Completion

```
[${SID}] Step N: <step-name> — <1-line result>
   Next: [${SID}] Step N+1: <next-step-name>
   Progress: X/Y tasks complete across Z stories
```

### After Each Story Completion

```
## Story ${SID} Complete

| Step | Status | Key Output |
|------|--------|------------|
| 1    | done   | ...        |
| ...  | ...    | ...        |

Tests: [count] passing | Typecheck: clean | Build: done
Stories remaining: [count]
```

### Progress Checkpoint (After Every Wave)

```
## Sprint Progress — [timestamp]

| Story | Current Step | Status | Tests | Issues |
|-------|-------------|--------|-------|--------|
| A-1   | Step 5      | impl   | 12    | 0      |
| A-2   | Step 1      | wait   | —     | —      |

Tasks: X completed / Y total | ETA: ~Z steps remaining
```

## Decision Points (Unattended Defaults)

All decision points run unattended by default; outcomes that previously paused for input are now resolved by best-judgment and logged to `${DEFERRED_DECISIONS_PATH}`. The only hard pause is ambiguous merge conflicts (Step 6/9). This fork is personal — no opt-out flags. If you ever want a pause back, edit this section.

<decision-rules>
1. **Phase 0 plan presentation:** No pause. Print the plan to stdout for transcript visibility, append a "Sprint plan committed" entry to `${DEFERRED_DECISIONS_PATH}` (`confidence: high, needs_human_review: no`), and proceed straight to the wave-loop.

2. **Step 1 (create-story) post-create review:** No pause. Story flows straight to Step 2. Step 3 (BMAD-checklist validate) is the new quality gate after Step 1 — that runs unattended in fresh context and logs findings.

3. **Step 3 (validate) FAIL handling:** Auto-correct + log + block-on-second-fail. On first FAIL, spawn one corrective sub-agent (Opus, `subagent_type: general-purpose`) that reads the FAIL findings + the story file + the epic file, applies fixes for Critical-tier findings to the story file, and re-runs the BMAD checklist. If the second run still FAILs: mark the story `blocked`, append a `confidence: low, needs_human_review: yes` entry to `${DEFERRED_DECISIONS_PATH}`, and continue with other stories in the sprint. (Never an infinite retry loop — exactly one auto-correction pass.)

4. **Step 7 (consolidated review) action items:** Auto-route by severity. Critical and High → straight to Step 8 for fix. Medium and Low → append to `${DEFERRED_DECISIONS_PATH}` with `needs_human_review: yes` and skip the fix. If only Medium/Low items exist (no Critical or High): mark Steps 8 AND 9 completed immediately and proceed to Step 10. (The user-presentation block from older versions is gone.)

5. **Step failure handling:** Retry-once-then-skip. On step failure, log the error to `${DEFERRED_DECISIONS_PATH}` (`confidence: low, needs_human_review: yes`) and retry the same step once with the same agent. If the second attempt fails: mark the story `blocked`, log a follow-up entry, and continue with other independent stories in the sprint. Bounded retries — never an infinite loop.

6. **Size M+ story detected in Phase 0:** Log-and-proceed. Append a `confidence: medium, needs_human_review: yes, suggested action: 'consider decomposing'` entry to `${DEFERRED_DECISIONS_PATH}` and proceed without blocking. The user reviews post-sprint.

7. **Context getting heavy:** After completing a story, suggest session refresh if 2+ stories remain. (No pause; advisory only.)

8. **Ambiguous merge conflicts (Step 6 or 9) — THE ONLY HARD PAUSE:** If Amelia reports a conflict as ambiguous (unclear which side is correct), the coordinator surfaces the conflict to the user immediately, blocks ONLY that story, and continues other independent stories. The deferred-decisions log captures the block; the sprint pauses on that one story until the user resolves it.
</decision-rules>

## Review Continuation Note

Step 5 (Implementation) can detect a "Senior Developer Review (AI)" section in the story file. If present, this indicates a prior review cycle. The implementation agent should treat review feedback as additional constraints and verify that prior review items have been addressed in the current implementation.

## Error Recovery

<error-recovery>
- **Agent timeout/crash:** Mark task as pending (not completed), log to `${DEFERRED_DECISIONS_PATH}` (`confidence: low, needs_human_review: yes`), retry once per Decision Point #5. On second failure, mark the story `blocked` and continue with other stories.
- **Test failures in Step 5:** Agent should attempt to fix. If still failing after implementation, log to `${DEFERRED_DECISIONS_PATH}` and surface in the agent's return; the coordinator applies retry-once-then-block per Decision Point #5.
- **Build failure:** Same as test failure — agent attempts fix, then retry-once-then-block.
- **Circular story dependency:** Detected in Phase 0, reported immediately, pipeline does not start.
- **All stories failed:** Output summary of failures and the deferred-decisions log path; suggest `/bmad-correct-course`.
- **Post-merge rollback (Step 7 finds critical issue after Step 6 merge):**
  1. Amelia identifies the merge commit hash from Step 6 output
  2. Run: `git revert <merge-commit-hash> --no-edit` (creates a revert commit, preserving history; commit message generated under ${ANTI_LEAK_BLOCK})
  3. Verify: `${test_command} && ${typecheck_command} && ${build_command}` (working branch is clean again)
  4. Append a deferred-decisions entry: merge reverted, story blocked, action items listed
  5. Step 8 fixes then run in worktree starting from the pre-merge state
  6. After fixes: re-merge via a new Step 6 invocation (Amelia merges the fixed branch)
  7. NEVER use `git reset --hard` — revert preserves history and is safe for shared branches
</error-recovery>

## Sprint Summary (Final Output)

After ALL stories complete (or fail):

```
## Enhanced Sprint Complete — Epic ${EPIC_ID}

### Story Results
| Story | Status | Tests Added | Files Changed | Issues Fixed | Duration |
|-------|--------|-------------|---------------|-------------|----------|
| ${SID} | done/fail | [count]  | [count]       | [count]     | ~steps   |
| ...   | ...    | ...         | ...           | ...         | ...      |

### Aggregate Metrics
- Total tests: [count] passing (was [before], +[delta])
- Typecheck: clean
- Build: passing
- Stories completed: [count] / [total]
- Action items found & fixed: [count]

### Deferred Decisions
- Entries logged this sprint: [count]
- Path: ${DEFERRED_DECISIONS_PATH}
- Review before pushing: open the file and resolve any `needs_human_review: yes` entries.

### Epic Status
- Epic ${EPIC_ID}: [in-progress / done]
- Remaining stories: [list or "none — epic complete!"]

### Sprint Status File Updated
- [list all status changes made to sprint-status.yaml]

### Auto-commit Summary
- Stories with auto-commits: [count]
- Submodule commits: [count across all stories]
- Main repo commits: [count]
- Anti-leak checks: all pass / [N] flagged for manual review (see deferred-decisions log)
- Reminder: NO auto-push. Review and `git push` manually when satisfied.
```

## Model Assignment Summary

| Step | Model | Isolation | Rationale |
|------|-------|-----------|-----------|
| Phase 0: Discovery | coordinator | — | Reads YAML/MD, creates tasks, compiles epic-context cache, initializes deferred-decisions log — no agent needed (epic-context compile spawns one sub-agent only on cache miss) |
| Step 1: Create story | opus | — | Story authoring needs deep epic context understanding |
| Step 2: Elicitation | opus | — | Method selection requires nuanced judgment |
| Step 3: Validate (BMAD checklist runner) | opus | — | Fresh-context independent re-analysis using BMAD's authoritative checklist; auto-fix Critical, log Enhancement/Optimization |
| Step 4: TDD E2E | sonnet | — | E2E test generation from ACs, speed matters |
| Step 5: Implementation | sonnet | **worktree** | Longest step, worktree enables parallel execution across stories; Amelia writes Kent-Beck-style unit tests inline |
| Step 6: Merge impl | **opus** | — | **BMAD Dev Agent (Amelia)** — senior engineer merge judgment, conflict resolution, post-merge verification (NO auto-commit) |
| Step 7: Consolidated review | opus | — | BMAD 6.4 runs Blind Hunter + Edge Case Hunter + Acceptance Auditor internally; Acceptance Auditor's per-AC verdict supplants the dropped AC-trace step |
| Step 8: Fixes | sonnet | **worktree** | Targeted fixes for Critical/High items in isolation, parallelizable across stories |
| Step 9: Merge fixes + auto-commit | **opus** | — | **BMAD Dev Agent (Amelia)** — same merge protocol as Step 6 PLUS the per-story auto-commit sequence (submodule-first, then main repo, anti-leak applied; never auto-pushes) |
| Step 10: Sprint status | coordinator | — | Delegates to `/bmad-sprint-status` sequentially |
