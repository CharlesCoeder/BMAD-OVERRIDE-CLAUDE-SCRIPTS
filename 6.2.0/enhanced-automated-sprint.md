---
name: 'enhanced-automated-sprint'
description: 'Run the full BMAD pipeline for multiple stories in an epic. Breaks stories into manageable tasks, tracks progress with TaskCreate/TaskUpdate, and uses focused agents for context efficiency. Supports parallel story execution.'
---

# Enhanced Automated Sprint Pipeline

> **TL;DR for humans:** This skill automates the entire dev lifecycle for multiple stories in an epic. You give it an epic ID (and optionally specific story IDs), and it runs each story through: **create -> refine -> validate -> write unit tests -> write E2E tests -> implement -> consolidated code review -> fix issues -> verify -> update sprint status**. BMAD 6.2's `/bmad-bmm-code-review` now runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally — no separate adversarial/edge-case steps needed. Stories can run in parallel when independent. You approve the plan upfront and get prompted at key decision points (story review, fix prioritization, failures). Everything else is hands-off.
>
> **Usage:** `/enhanced-automated-sprint 7` or `/enhanced-automated-sprint 7 7-1 7-2 --parallel 2`
>
> | Step | What It Does | BMAD Command | Model | Parallel? |
> |------|-------------|--------------|-------|-----------|
> | 1 | Create story from epic | `/bmad-bmm-create-story` | Opus | Yes |
> | 2 | Refine story via elicitation | _(auto-apply methods)_ | Opus | Yes |
> | 3 | Validate story against epic | `/bmad-bmm-create-story validate` | Opus | Yes |
> | 4 | Write TDD unit tests (red phase) | `/bmad-bmm-qa-automate TDD` | Sonnet | Yes |
> | 4b | Write TDD E2E tests (red phase) | `/bmad-qa-generate-e2e-tests` | Sonnet | Yes (parallel with 4) |
> | 5 | Implement code to pass all tests | `/bmad-bmm-dev-story` | Sonnet | Yes (worktree) |
> | 6 | Merge implementation branch | _(Amelia dev agent)_ | Opus | No (sequential) |
> | 7 | Consolidated code review | `/bmad-bmm-code-review` | Opus | Yes |
> | 8 | Fix review action items | _(targeted fixes)_ | Sonnet | Yes (worktree) |
> | 9 | Merge fix branch | _(Amelia dev agent)_ | Opus | No (sequential) |
> | 10 | Trace ACs to test coverage | `/bmad-bmm-qa-automate TRACE` | Sonnet | Yes |
> | 11 | Update sprint status | `/bmad-bmm-sprint-status` | Coordinator | No (sequential) |

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
```

The coordinator expands `${BMAD_ENV_BLOCK}` to the fully resolved block above at spawn time. Every agent receives the same environment. No variable is withheld.
</env-block>

## Input Format

```
$ARGUMENTS = <EPIC_ID> [STORY_IDS...] [--parallel N] [--skip-elicitation] [--auto-fix]
```

**Examples:**
- `/enhanced-automated-sprint 5` — All `ready-for-dev` + `backlog` stories in Epic 5
- `/enhanced-automated-sprint 5 5-1 5-2` — Only stories 5-1 and 5-2
- `/enhanced-automated-sprint 5 --parallel 2` — Epic 5, run up to 2 stories in parallel
- `/enhanced-automated-sprint 5 5-1 --skip-elicitation` — Skip Step 2 for speed

**Defaults:** `--parallel 1` (sequential), elicitation ON, auto-fix OFF

**Story status mapping:** BMAD 6.2 uses `ready-for-dev` as the primary status. The legacy `drafted` status is auto-mapped to `ready-for-dev` for backward compatibility. The coordinator accepts both.

**E2E tests:** Step 4b (E2E TDD) always runs in parallel with Step 4 (unit TDD). Both are blocked by Step 3 (validation) and both feed into Step 5 (implementation). The implementation agent must make all unit AND E2E tests pass.

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
5. **Build `${BMAD_ENV_BLOCK}`** — expand the Agent Environment Block template with all resolved values. This block is injected into every agent prompt for the rest of the pipeline.
6. **Parse `$ARGUMENTS`** — extract EPIC_ID, optional STORY_IDS, and flags.
7. **Read sprint-status.yaml** at `{implementation_artifacts}/sprint-status.yaml`
8. **Identify target stories:**
   - If STORY_IDS provided: use exactly those
   - If only EPIC_ID: collect all stories with status `ready-for-dev`, `backlog`, or `drafted` (legacy — auto-mapped to `ready-for-dev`). Skip `done`, `in-progress`.
9. **Read the epic file** at `{planning_artifacts}/epic-${EPIC_ID}.md` to understand story dependencies and ordering
10. **Determine story execution order:**
   - Stories with no inter-story dependencies can run in parallel (up to `--parallel N`)
   - Stories that depend on other stories in the batch must run after their dependency completes
   - Default: sequential in story number order
11. **Size check:** If any story is Size M or larger, warn the user and suggest breaking it into Size S stories before proceeding
12. **Create the task list** using TaskCreate (see Task Structure below)
13. **Present the plan** to the user and wait for approval before proceeding
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
| `[${SID}] Step 4: TDD unit test generation` | `Generating TDD unit tests for ${SID}` | `[${SID}] Step 3: Validate story` |
| `[${SID}] Step 4b: TDD E2E test generation` | `Generating TDD E2E tests for ${SID}` | `[${SID}] Step 3: Validate story` |
| `[${SID}] Step 5: Implementation` | `Implementing story ${SID}` | `[${SID}] Step 4: TDD unit test generation`, `[${SID}] Step 4b: TDD E2E test generation` |
| `[${SID}] Step 6: Merge implementation` | `Merging ${SID} implementation to main branch` | `[${SID}] Step 5: Implementation` |
| `[${SID}] Step 7: Consolidated code review` | `Reviewing code for ${SID}` | `[${SID}] Step 6: Merge implementation` |
| `[${SID}] Step 8: Fix action items` | `Fixing review items for ${SID}` | `[${SID}] Step 7: Consolidated code review` |
| `[${SID}] Step 9: Merge fixes` | `Merging ${SID} review fixes to main branch` | `[${SID}] Step 8: Fix action items` |
| `[${SID}] Step 10: AC trace` | `Tracing ACs for ${SID}` | `[${SID}] Step 9: Merge fixes` |
| `[${SID}] Step 11: Update sprint status` | `Updating sprint status for ${SID}` | `[${SID}] Step 10: AC trace` |

**\*** Coordinator sets Step 1 `blockedBy` dynamically: no blocker in parallel mode, previous story's Step 11 in sequential mode (`--parallel 1`), or inter-story dependency's Step 11 if epic defines one.

If `--skip-elicitation`: ALWAYS create Step 2 in the task graph (keeps the dependency chain intact), but mark it as `completed` immediately at creation time. This avoids conditional task graph construction — Step 3 still blocks on Step 2, which is already done.

### Cross-Story Dependencies

- **Sequential mode** (`--parallel 1`): Story B's Step 1 is blocked by Story A's Step 11
- **Parallel mode** (`--parallel N`): No cross-story `blockedBy` for independent stories — the **coordinator** enforces parallelism limits and merge gates (Steps 6, 9) at spawn time, NOT via task dependencies. This keeps the task graph simple and avoids false blocking.
  - Exception: Stories WITH inter-story dependencies (noted in epic file) DO get `blockedBy` on their dependency's Step 11.
- **Worktree isolation** (Steps 5, 8): These steps run in git worktrees (`isolation: "worktree"`), so they CAN run in parallel across stories. Each agent gets its own repo copy — no file conflicts during implementation.
- **Merge gates** (Steps 6, 9): After worktree work completes, the **BMAD Dev Agent (Amelia — Senior Software Engineer)** integrates the worktree branch back to the working branch. Merges run SEQUENTIALLY (one at a time) to avoid merge race conditions. Amelia resolves conflicts with senior-level judgment, verifies all tests pass post-merge, and speaks in file paths and AC IDs — no fluff.

### Epic-Level Tasks

| Task Subject | ActiveForm | Blocked By |
|---|---|---|
| `[Epic ${EPIC_ID}] Cross-story integration check` | `Running cross-story integration verification` | All stories' Step 11 |
| `[Epic ${EPIC_ID}] Sprint summary` | `Generating sprint summary` | `[Epic ${EPIC_ID}] Cross-story integration check` |

**Cross-story integration check** runs AFTER all stories are individually complete. It verifies that stories don't break each other when combined:
1. Run: `${test_command}` — full test suite (catches cross-story conflicts like duplicate routes, naming collisions)
2. Run: `${typecheck_command}` — type check (catches cross-story type conflicts)
3. Run: `${build_command}` — full build (catches cross-story import/bundling issues)
4. If any check fails: report failing tests/errors, identify which stories' files are involved, ask user whether to fix or rollback
5. If all pass: mark as completed, proceed to sprint summary

## Execution Engine: Parallel Story Processing

<parallel-execution CRITICAL="TRUE">
The coordinator runs a **wave-based execution loop**. Each iteration:

1. **Call TaskList** — get all tasks and their statuses
2. **Identify ALL unblocked tasks** — tasks where every `blockedBy` dependency is `completed`
3. **Group unblocked tasks by concurrency rules:**
   - Steps 1, 2, 3 (story creation/elicitation/validation): **PARALLEL** — no shared files
   - Step 4 (TDD unit): **PARALLEL** — safe because test files are story-scoped. Each agent writes only to its own story's test files. If stories share a test file, fall back to SEQUENTIAL for Step 4.
   - Step 4b (TDD E2E): **PARALLEL** — same safety as Step 4, E2E test files are story-scoped. Runs in the SAME wave as Step 4 — both are unblocked by Step 3.
   - Step 5 (implementation): **PARALLEL in worktrees** — `isolation: "worktree"` gives each agent its own repo copy
   - Steps 6, 9 (merges): **SEQUENTIAL** — merge one worktree branch at a time to avoid race conditions
   - Step 7 (consolidated review): **PARALLEL** — read-only analysis. BMAD 6.2 runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally within a single `/bmad-bmm-code-review` invocation.
   - Step 8 (fixes): **PARALLEL in worktrees** — same worktree isolation as Step 5
   - Step 10: **PARALLEL** — read-only analysis
   - Step 11: **COORDINATOR-SEQUENTIAL** — delegates to `/bmad-bmm-sprint-status` one story at a time. Two concurrent writes to the same YAML file = data loss.
4. **Spawn agents for ALL parallelizable unblocked tasks in a SINGLE message** — this is how Claude Code runs agents concurrently. Multiple Task tool calls in one response = true parallelism.
5. **Wait for all spawned agents to complete**
6. **Mark completed tasks, report results, loop back to step 1**

### Parallelism Example

Given stories A-1 and A-2 with `--parallel 2` and no inter-story dependencies:

```
Wave 1:  [A-1] Step 1 + [A-2] Step 1         parallel (story creation)
Wave 2:  [A-1] Step 2 + [A-2] Step 2         parallel (elicitation)
Wave 3:  [A-1] Step 3 + [A-2] Step 3         parallel (validation)
Wave 4:  [A-1] Step 4 + [A-1] Step 4b + [A-2] Step 4 + [A-2] Step 4b
                                               parallel (unit TDD + E2E TDD)
Wave 5:  [A-1] Step 5 + [A-2] Step 5         parallel IN WORKTREES
Wave 6:  [A-1] Step 6                         SEQUENTIAL merge
Wave 7:  [A-2] Step 6                         SEQUENTIAL merge
Wave 8:  [A-1] Step 7 + [A-2] Step 7         parallel (consolidated review)
Wave 9:  [A-1] Step 8 + [A-2] Step 8         parallel IN WORKTREES (fixes)
Wave 10: [A-1] Step 9                         SEQUENTIAL merge
Wave 11: [A-2] Step 9                         SEQUENTIAL merge
Wave 12: [A-1] Step 10 + [A-2] Step 10       parallel (AC trace)
Wave 13: [A-1] Step 11, then [A-2] Step 11   COORDINATOR-SEQUENTIAL
```

**Speedup:** 13 waves vs 20+ sequential steps. BMAD 6.2's consolidated review (Blind Hunter + Edge Case Hunter + Acceptance Auditor in a single invocation) replaces the 3 separate review agents from prior versions, reducing review from 3 parallel agents to 1 without losing coverage. Implementation (the longest step) runs concurrently across stories.

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
| Step 6: Merge implementation | Merge worktree branch from Step 5 into working branch | **BMAD Dev Agent (Amelia)** — Opus |
| Step 9: Merge fixes | Merge worktree branch from Step 8 into working branch | **BMAD Dev Agent (Amelia)** — Opus |

All other steps parallelize freely because they either:
- Write to story-specific files (Steps 1, 2, 4, 4b)
- Run in isolated worktrees (Steps 5, 8)
- Are read-only analysis (Steps 3, 7, 10)

Step 11 delegates to `/bmad-bmm-sprint-status` and runs sequentially (shared `sprint-status.yaml` file).
</parallel-execution>

## Execution Rules

<rules CRITICAL="TRUE">
1. **Act as COORDINATOR** — delegate all work via Task tool agents, do NOT execute pipeline steps yourself
2. **One agent per step** — each step spawns a focused Task agent. Do NOT pass full conversation history. DO pass `${BMAD_ENV_BLOCK}` to every agent — environment variables are configuration, not history.
3. **PARALLEL by default** — when multiple tasks are unblocked AND parallelizable (see Sequential Gate Rules above), spawn them ALL in a single message. This is the core performance advantage of the enhanced pipeline.
4. **TaskUpdate before and after** — mark task `in_progress` BEFORE spawning the agent, mark `completed` AFTER agent succeeds
5. **TaskList after each wave** — check what's unblocked next
6. **Failure stops the STORY, not the sprint** — if a step fails for one story, mark it failed, report to user, but continue with other stories if they're independent
7. **Context budget per agent:** Each agent should read at most 5-8 files. If a step needs more context, break it into sub-agents.
8. **Steps 8 + 9 are conditional** — only create a fix agent if Step 7 produced action items. If Step 7 (consolidated review) reports no action items, mark BOTH 8 AND 9 as completed immediately and proceed to Step 10.
8a. **Tasks/Subtasks validation gate** — after Step 5 completes, the coordinator MUST check the agent's return for "Tasks/Subtasks completion". If the agent reports incomplete tasks or does NOT confirm story file was updated, the coordinator MUST flag this to the user before proceeding. The story file's `## Tasks / Subtasks` section is the source of truth for implementation completeness — test results alone are NOT sufficient.
9. **Step 11 uses BMAD** — delegate to `/bmad-bmm-sprint-status` to update sprint-status.yaml, one story at a time (sequential)
10. **Progress checkpoints** — after every wave, output a progress summary to the user
11. **If context feels heavy** — after completing a full story's pipeline, output a handoff summary and suggest the user refresh the session if more stories remain
12. **Skill invocation** — BMAD 6.2 uses `.claude/skills/` with `SKILL.md` entry points. When invoking `/bmad-*` skills inside agents, the coordinator should verify skill paths match the detected `${SKILL_ARCH}` from Phase 0. If skills are in `.claude/skills/`, agents invoke them as `/bmad-*` (unchanged command name). If the Skill tool is unavailable inside Task agents, fall back to inline-workflow mode.
</rules>

## Agent Spawn Templates

### Focused Agent Pattern

Each agent gets a **minimal, focused prompt** plus the full `${BMAD_ENV_BLOCK}` — only step-specific context varies, environment is always included.

**NOTE:** Templates below are pseudo-code showing the Task tool parameters. The coordinator translates these to actual Task tool calls with JSON parameters. All named parameters (`description`, `subagent_type`, `model`, `isolation`, `prompt`) are real Task tool parameters. The `<-` inline comments are documentation only — do not include them in actual tool calls.

**SKILL INVOCATION WARNING:** Steps 1, 3, 4, 4b, 5, 7, and 10 invoke `/bmad-*` skills or workflows inside Task agents. If the Skill tool is not available inside Task agents, the coordinator MUST use a fallback: instead of `Execute: /bmad-bmm-create-story ${SID}`, load the skill's workflow YAML directly and pass its instructions inline in the prompt. The coordinator should test skill availability in Phase 0 by spawning a lightweight probe agent that attempts `/bmad-help` — if it fails, switch all templates to inline-workflow mode. In BMAD 6.2, skills live under `.claude/skills/` with `SKILL.md` entry points.

#### Step 1: Create Story
```
Task tool:
  description: "[${SID}] Create story"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    Run the BMAD create-story workflow for story ${SID}.
    Execute: /bmad-bmm-create-story ${SID}

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

#### Step 3: Validate Story
```
Task tool:
  description: "[${SID}] Validate"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    Validate story ${SID} against its epic.
    Execute: /bmad-bmm-create-story validate ${SID}

    Story file: ${STORY_FILE_PATH}
    Epic file: {planning_artifacts}/epic-${EPIC_ID}.md

    Return to coordinator: PASS/FAIL, AC match count, scope drift, missing ACs, action items.
```

#### Step 4: TDD Unit Test Generation
```
Task tool:
  description: "[${SID}] TDD unit tests"
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    ${BMAD_ENV_BLOCK}

    Generate TDD unit tests for story ${SID}.
    Execute: /bmad-bmm-qa-automate TDD ${SID} yolo

    Story file: ${STORY_FILE_PATH}

    Save TDD test report to: {implementation_artifacts}/${SID}-tdd-test-report.md

    Return to coordinator:
    - Test file paths created
    - Test count
    - AC coverage (which ACs are covered by which tests)
    - Red phase confirmation (all tests fail as expected)
    - Report file path: {implementation_artifacts}/${SID}-tdd-test-report.md
```

#### Step 4b: TDD E2E Test Generation
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

**Coordinator note:** Step 4b runs in PARALLEL with Step 4 — both are unblocked by Step 3. Step 5 blocks on BOTH Step 4 and Step 4b.

#### Step 5: Implementation (Worktree Isolated)
```
Task tool:
  description: "[${SID}] Implement"
  subagent_type: general-purpose
  model: sonnet
  isolation: "worktree"          <- agent gets its own repo copy (only when parallel)
  prompt: |
    ${BMAD_ENV_BLOCK}

    Implement story ${SID} by following the story file's Tasks/Subtasks section.
    Execute: /bmad-bmm-dev-story ${SID} yolo

    Story file: ${STORY_FILE_PATH}
    Unit test files: ${TEST_FILE_PATHS}
    E2E test files: ${E2E_TEST_FILE_PATHS}

    CRITICAL — STORY FILE TASK TRACKING:
    The story file at ${STORY_FILE_PATH} contains a "## Tasks / Subtasks" section with checkboxes.
    You MUST follow the dev-story workflow's task-driven implementation loop:
    1. Find the first incomplete task (unchecked [ ]) in "Tasks / Subtasks"
    2. Implement that specific task (use existing TDD tests from ${TEST_FILE_PATHS} as verification)
    3. When the task's tests pass AND implementation matches the task spec, mark it [x] in the story file
    4. Update the story file's "Dev Agent Record" and "File List" sections
    5. Loop back to step 1 until ALL tasks/subtasks are marked [x]

    NOTE: TDD tests already exist from prior pipeline steps. Use them as your verification —
    do NOT regenerate tests that already exist. You may add additional tests if the existing
    TDD tests do not cover a specific task's requirements.

    ALL TESTS MUST PASS: Both unit tests (${TEST_FILE_PATHS}) and E2E tests (${E2E_TEST_FILE_PATHS})
    must pass.

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

    You are Amelia, the BMAD Developer Agent — a Senior Software Engineer.
    Your identity: Execute with strict adherence to story details and team standards.
    Your communication style: Ultra-succinct. Speak in file paths and AC IDs — every statement citable. No fluff, all precision.
    Your principle: All existing and new tests must pass 100%.

    ## Your Role
    You are the quality gate between isolated implementation and the shared codebase.
    You merge with the judgment of a senior engineer — not blindly.

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
       - Run: git merge ${WORKTREE_BRANCH} --no-ff -m "feat: merge story ${SID} implementation"
       - If clean merge: proceed to verification
       - If conflicts: resolve them with senior judgment (see sub-step 4 below — Conflict Resolution)

    4. **Conflict Resolution (if needed):**
       - Read BOTH versions of conflicting files fully
       - Read the story file to understand the INTENT of the changes
       - Resolve by preserving both stories' functionality — never silently drop one side
       - If a conflict is ambiguous (unclear which side is correct), STOP and report to coordinator
       - After resolving: git add <resolved files> && git commit -m "merge: resolve ${SID} conflicts"

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
```

#### Step 7: Consolidated Code Review
```
Task tool:
  description: "[${SID}] Consolidated review"
  subagent_type: general-purpose
  model: opus
  prompt: |
    ${BMAD_ENV_BLOCK}

    Run the BMAD 6.2 consolidated code review for story ${SID}.
    Execute: /bmad-bmm-code-review ${SID} yolo

    Story file: ${STORY_FILE_PATH}
    Implementation files: ${IMPL_FILE_PATHS}
    Test files: ${TEST_FILE_PATHS}

    BMAD 6.2's code review runs 3 internal review passes:
    1. Blind Hunter — architectural and security review
    2. Edge Case Hunter — method-driven path enumeration for unhandled edge cases
    3. Acceptance Auditor — AC-by-AC verification of implementation completeness

    All three run within a single /bmad-bmm-code-review invocation. You do NOT need to
    invoke them separately.

    Return to coordinator:
    - Overall verdict: PASS / PASS WITH ITEMS / FAIL
    - Findings table with source attribution:
      (# | source [blind/edge/acceptance] | severity | category | finding | recommendation)
    - Critical count (by source)
    - Total action item count
    - Edge case findings in JSON format (for Step 8 if fixes needed):
      [{location, trigger_condition, guard_snippet, potential_consequence}, ...]
    - AC verification count (from acceptance auditor)
```

**Coordinator note:** This single step replaces the old Steps 7 (code review), 8 (adversarial review), and 8b (edge case hunter) from BMAD 6.0.x. BMAD 6.2 runs all three review types internally. The coordinator receives unified findings with source attribution and passes them to Step 8 if fixes are needed.

#### Step 8: Fix Action Items (Conditional, Worktree Isolated)
```
Task tool:
  description: "[${SID}] Fix review items"
  subagent_type: general-purpose
  model: sonnet
  isolation: "worktree"          <- fixes run in isolated worktree (only when parallel)
  prompt: |
    ${BMAD_ENV_BLOCK}

    Fix the following action items from the consolidated code review for story ${SID}.
    The review included findings from Blind Hunter, Edge Case Hunter, and Acceptance Auditor.

    Items to fix:
    ${CONSOLIDATED_ACTION_ITEMS}

    Edge case findings (JSON — add guards for critical ones):
    ${EDGE_CASE_FINDINGS}

    Implementation files: ${IMPL_FILE_PATHS}
    Test files: ${TEST_FILE_PATHS}

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

**Coordinator note:** Save worktree branch/path from result for Step 9. If Step 8 was skipped (no action items from Step 7), also skip Step 9.

#### Step 9: Merge Fixes (BMAD Dev Agent — SEQUENTIAL)

Same agent template as Step 6 (Amelia, Senior Software Engineer persona), but with:
- Description: `"[${SID}] Dev merge fixes"`
- Commit message: `"fix: merge story ${SID} review fixes"`
- Worktree branch/path from Step 8 result
- `${BMAD_ENV_BLOCK}` included in prompt (same as Step 6)

#### Step 10: AC Trace
```
Task tool:
  description: "[${SID}] AC trace"
  subagent_type: general-purpose
  model: sonnet
  prompt: |
    ${BMAD_ENV_BLOCK}

    Trace all acceptance criteria to test coverage for story ${SID}.
    Execute: /bmad-bmm-qa-automate TRACE ${SID} yolo

    Story file: ${STORY_FILE_PATH}
    Test files: ${TEST_FILE_PATHS}
    Implementation files: ${IMPL_FILE_PATHS}

    Save AC trace report to: {implementation_artifacts}/${SID}-ac-trace-report.md

    Return to coordinator:
    - AC trace matrix (AC ID -> test file:test name -> PASS/FAIL)
    - Total tests passing
    - Coverage gaps (ACs without test coverage)
    - Implementation file list
    - Report file path: {implementation_artifacts}/${SID}-ac-trace-report.md
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

## Decision Points & User Interaction

<decision-rules>
1. **Step 1 (create-story):** ALWAYS pause for user review of ACs and dev notes before proceeding
2. **Step 3 (validate):** If FAIL -> stop that story, ask user how to proceed
3. **Step 7 (consolidated review):** If action items found:
   - `--auto-fix`: auto-proceed to Step 8 with all items
   - Default: present items (with source attribution: blind/edge/acceptance), ask user which to fix (all / medium+ / skip)
4. **Step failure:** Report error, mark story as blocked, ask user: retry / skip story / stop sprint
5. **Size M+ story detected in Phase 0:** Warn and suggest decomposition before starting
6. **Context getting heavy:** After completing a story, suggest session refresh if 2+ stories remain
</decision-rules>

## Review Continuation Note

Step 5 (Implementation) can detect a "Senior Developer Review (AI)" section in the story file. If present, this indicates a prior review cycle. The implementation agent should treat review feedback as additional constraints and verify that prior review items have been addressed in the current implementation.

## Error Recovery

<error-recovery>
- **Agent timeout/crash:** Mark task as pending (not completed), report to user, offer retry
- **Test failures in Step 5:** Agent should attempt to fix. If still failing after implementation, report failing tests and stop that story's pipeline.
- **Build failure:** Same as test failure — agent attempts fix, escalates if stuck
- **Circular story dependency:** Detected in Phase 0, reported immediately, pipeline does not start
- **All stories failed:** Output summary of failures, suggest `/bmad-bmm-correct-course`
- **Post-merge rollback (Step 7 finds critical issue after Step 6 merge):**
  1. Amelia identifies the merge commit hash from Step 6 output
  2. Run: `git revert <merge-commit-hash> --no-edit` (creates a revert commit, preserving history)
  3. Verify: `${test_command} && ${typecheck_command} && ${build_command}` (working branch is clean again)
  4. Report to user: merge reverted, story blocked, action items listed
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

### Epic Status
- Epic ${EPIC_ID}: [in-progress / done]
- Remaining stories: [list or "none — epic complete!"]

### Sprint Status File Updated
- [list all status changes made to sprint-status.yaml]
```

## Model Assignment Summary

| Step | Model | Isolation | Rationale |
|------|-------|-----------|-----------|
| Phase 0: Discovery | coordinator | — | Reads YAML/MD, creates tasks — no agent needed |
| Step 1: Create story | opus | — | Story authoring needs deep epic context understanding |
| Step 2: Elicitation | opus | — | Method selection requires nuanced judgment |
| Step 3: Validate | opus | — | Cross-referencing epic vs story for drift |
| Step 4: TDD unit | sonnet | — | Pattern-based test generation, speed matters |
| Step 4b: TDD E2E | sonnet | — | E2E test generation from ACs, speed matters |
| Step 5: Implementation | sonnet | **worktree** | Longest step, worktree enables parallel execution across stories |
| Step 6: Merge impl | **opus** | — | **BMAD Dev Agent (Amelia)** — senior engineer merge judgment, conflict resolution, post-merge verification |
| Step 7: Consolidated review | opus | — | BMAD 6.2 runs Blind Hunter + Edge Case Hunter + Acceptance Auditor internally |
| Step 8: Fixes | sonnet | **worktree** | Targeted fixes in isolation, parallelizable across stories |
| Step 9: Merge fixes | **opus** | — | **BMAD Dev Agent (Amelia)** — same merge protocol as Step 6 |
| Step 10: AC trace | sonnet | — | Systematic tracing, speed matters |
| Step 11: Sprint status | coordinator | — | Delegates to `/bmad-bmm-sprint-status` sequentially |
