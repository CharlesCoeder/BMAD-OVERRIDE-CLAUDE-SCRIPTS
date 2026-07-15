---
name: 'enhanced-automated-sprint'
description: 'Run the full BMAD pipeline (BMAD 6.8-targeted) for multiple stories in an epic. Breaks stories into manageable tasks, tracks progress with TaskCreate/TaskUpdate, and uses focused agents for context efficiency. Supports parallel story execution. Unattended-by-default with anti-leak commit messages, auto-commit (incl. submodules), a deferred-decisions log, and an always-on per-step token-usage log.'
---

<!-- BMAD 6.6.0 → 6.8.0 audit (do not delete)
- 6.7.0/6.7.1: PRD + product-brief rebuilt (bmad-prd / bmad-product-brief with Create/Update/Validate intents), new bmad-investigate skill, `.decision-log.md` pattern, community-modules installer changes. NONE are Phase-4 implementation skills this pipeline invokes — no interface impact. The `.decision-log.md` is written ONLY by planning skills (bmad-prd, bmad-ux, bmad-product-brief, bmad-spec); it never coexists with this skill's deferred-decisions log inside the pipeline.
- 6.8.0 breaking changes are PLANNING surfaces the sprint does not consume: bmad-create-ux-design → bmad-ux (two-spine DESIGN.md + EXPERIENCE.md), bmad-distillator → bmad-spec. Story / epic / sprint-status / PRD doc formats remain forward-compatible — no document conversion required for this pipeline.
- Skill/command names verified UNCHANGED 6.6→6.8: /bmad-create-story, /bmad-dev-story, /bmad-code-review, /bmad-qa-generate-e2e-tests, /bmad-sprint-status, /bmad-correct-course. Story status vocabulary unchanged (backlog → ready-for-dev → in-progress → review → done).
- PATH FIX (stale since the .claude/skills/ move in 6.2): support files resolve under `.claude/skills/<skill>/`, NOT `_bmad/bmm/skills/` or `_bmad/core/workflows/`. The installer co-locates checklist.md / methods.csv / compile-epic-context.md inside each skill dir under .claude/skills/ and removes the redundant _bmad/ copies. Phase 0 now resolves `${BMAD_SKILLS_ROOT}` with a fallback cascade; Step 2 (methods.csv), Step 3 (checklist.md), and Phase 0 §9.3 (compile-epic-context.md) read through it.
- NEW dev-story behavior (#2403, baseline_commit): `/bmad-dev-story` stamps `baseline_commit: <git rev-parse HEAD>` into story frontmatter when status==ready-for-dev. `/bmad-code-review` step-01 reads that frontmatter and uses it as the diff baseline. Because Step 5 runs in a worktree and sibling stories may merge before Step 7, baseline_commit can over-scope the review — Step 7 now constrains code-review to the story File List. baseline_commit also gives code-review a deterministic baseline that avoids its interactive branch-confirm HALT — good for unattended mode.
- NEW variable (#2422, project_context): dev-story / sprint-planning / sprint-status / create-story / code-review now resolve `project_context = **/project-context.md` (load-if-exists). Optional; the skills self-resolve it. Added to ${BMAD_ENV_BLOCK} for completeness.
-->

<!-- 6.6.0 in-version revision: tier-adaptive pipeline (do not delete)
- Added Step 1.5 (Sonnet classifier) between Step 1 and Step 2. Per-story tier in {lite, standard, full} decides which downstream steps run.
  - lite: skips Steps 2, 3, 4 (elicitation, validation, E2E TDD)
  - standard: skips Step 2 only (default for most stories)
  - full: runs all steps (legacy behavior)
- Always-on steps regardless of tier: 1, 1.5, 5, 6, 7, 8, 9, 10. Step 7 already consolidates Edge Case Hunter + Acceptance Auditor internally per BMAD 6.4 (see audit table above).
- New input syntax: STORY_ID:tier suffix (e.g. 7-1:lite) and global --tier=lite|standard|full flag. Resolution order: --tier= > :suffix > auto-classifier.
- Skipped tasks are STILL created in the task graph and marked completed immediately via TaskUpdate (same mechanism as existing --skip-elicitation), preserving the dependency chain.
- Classifier runs even when overridden — its recommendation is logged to ${DEFERRED_DECISIONS_PATH} for post-sprint visibility.
- Rationale: smaller-scope stories were burning context on validation/elicitation/E2E that didn't pay off. Auto-classification + override flags let the user keep "always run the full pipeline" behavior with --tier=full.
- Rubric refinement (post-initial): AC count dropped as a tier trigger (BMAD stories naturally have 15-20 ACs even when scope is narrow). Replaced with implementation-file-count from the story File List as the real complexity signal. Migration risk marker split: additive migrations (CREATE TABLE/INDEX, new RLS, additive ALTER) → standard; destructive migrations (DROP, type narrowing, NOT NULL on existing column, data-overwriting backfill) → full. Validated against two real stories from the maintainer's project: one (additive migration + 9 files) → standard, one (single-file pure function + 18 ACs) → standard. Both correctly avoid full-tier over-classification.
-->

<!-- 2026-07-15 token-data revision (do not delete)
Driven by three consecutive sprints of harness-reported subagent usage logs — 22 stories, ~25.6M subagent tokens. Changes:
- Step 1.5 classifier: sonnet → HAIKU with a slim prompt (no ${BMAD_ENV_BLOCK}). Measured ~48k/story flat across all 22 stories (~90% fixed prompt overhead) for a keyword-scan + counting rubric. Safety guard added: a `lite` recommendation below high confidence is promoted to `standard` — under-classification (skipping validate/E2E on a story that needed them) is the only costly error direction; standard vs full boundary errors are cheap and self-correcting at review.
- Classifier is now SKIPPED when a tier override applies (--tier= or :suffix). Supersedes the 6.6 note "classifier runs even when overridden" — the always-run rule cost ~48k/story for log-only output.
- Step 9 (merge fixes + auto-commit): opus → SONNET. 22/22 stories showed pure git mechanics (avg 31–43k), zero judgment-requiring conflicts in sequential mode; leak scrubs are grep-driven. The ambiguous-conflict hard pause remains the escape hatch.
- Step 10 folded into the coordinator: per-story sprint-status.yaml update is a coordinator-inline YAML edit + grep verify (proven organically on two mid-sprint stories with no quality loss; the dedicated agent cost 52–71k/story and was creeping upward). ONE /bmad-sprint-status reconcile agent runs at epic close-out.
- Step 2 (elicitation) input capped: description/Story + ACs + Tasks/Subtasks + epic-context cache; Dev Notes read only selectively per-subsection. Step 2 grew ~50% (66k → 98k avg) across the three measured sprints from re-reading ever-larger story files, not from more method work. Methods operate on ACs/tasks/description; technical grounding comes from the distilled epic-context cache.
- Mid-epic context recompile: epic-context cache is recompiled after every 3rd completed story (validated in practice: create-story dropped ~40% — 224k → 138k — immediately after a mid-sprint recompile; within-sprint growth was +68–85% without it).
- Step 7 (review) liveness protocol: reviews are the #1 stall source (four incidents across the three measured sprints — the stall tax outgrew every per-step cost). Coordinator nudges a silent review agent via SendMessage (resume repeatedly worked and costs a fraction of a ~130k respawn) and MUST collect late child-hunter findings before Step 9 commits (in one incident, late child reports contained a real HIGH).
- Steps 5 and 8 standardized on OPUS across every surface (TL;DR table, spawn templates, model-assignment table) — all 22 measured story runs used opus; copies of this skill had drifted, with sonnet lingering in one or more of those surfaces. Added missing Step 1.5 row to the model table.
- NEW always-on token-usage log: the coordinator writes `{implementation_artifacts}/sprint-epic-${EPIC_ID}-token-usage.md` for every sprint (harness-reported subagent_tokens per spawn, incl. waste rows), no flag or user request needed. The tuning above was only possible because this data was captured manually across three sprints; now it's a default artifact. See "Token Usage Log (always on)".
-->

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

> **TL;DR for humans:** This skill automates the entire dev lifecycle for multiple stories in an epic. You give it an epic ID (and optionally specific story IDs), and it runs each story through: **create -> classify tier -> (refine) -> (validate) -> (write E2E tests) -> implement -> consolidated code review -> fix issues -> merge fixes (auto-commit) -> update sprint status**. After Step 1 a Haiku classifier picks a tier (`lite` / `standard` / `full`) per story; smaller-scope stories skip elicitation/validation/E2E to save context. BMAD 6.4's `/bmad-code-review` runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally — no separate adversarial/edge-case steps needed. Stories can run in parallel when independent. **Unattended by default**: every former pause point auto-resolves with best-judgment and logs to a deferred-decisions doc; the only hard pause is ambiguous merge conflicts. Every sprint also auto-writes a per-step **token-usage log** (`sprint-epic-<ID>-token-usage.md`) — no flag needed.
>
> **Usage:** `/enhanced-automated-sprint 7` or `/enhanced-automated-sprint 7 7-1:lite 7-2:full --parallel 2`
>
> | Step | What It Does | BMAD Command | Model | Tiers | Parallel? |
> |------|-------------|--------------|-------|-------|-----------|
> | 1 | Create story from epic | `/bmad-create-story` | Opus | all | Yes |
> | 1.5 | Classify story tier (lite/standard/full) | _(rubric over story file; skipped when tier is overridden)_ | Haiku | all | Yes |
> | 2 | Refine story via elicitation | _(auto-apply methods)_ | Opus | full | Yes |
> | 3 | Validate story (fresh-context BMAD checklist runner) | _(executes `bmad-create-story/checklist.md`)_ | Sonnet | standard, full | Yes |
> | 4 | Write TDD E2E tests (red phase) | `/bmad-qa-generate-e2e-tests` | Sonnet | standard, full | Yes |
> | 5 | Implement code to pass all tests (TDD unit tests written inline by Amelia) | `/bmad-dev-story` | Opus | all | Yes (worktree) |
> | 6 | Merge implementation branch | _(Amelia dev agent)_ | Opus | all | No (sequential) |
> | 7 | Consolidated code review | `/bmad-code-review` | Opus | all | Yes |
> | 8 | Fix review action items | _(targeted fixes)_ | Opus | all | Yes (worktree) |
> | 9 | Merge fix branch + auto-commit (incl. submodules) | _(Amelia dev agent)_ | Sonnet | all | No (sequential) |
> | 10 | Update sprint status | _(coordinator-inline YAML edit; one `/bmad-sprint-status` reconcile at epic close-out)_ | Coordinator | all | No (sequential) |

Run the full BMAD pipeline for **multiple stories** in an epic using task-based tracking and focused agents.

## Configuration

This skill uses BMAD config variables from two files (BMAD 6.6 split):
- `{project-root}/_bmad/core/config.yaml` — universal vars used by every module
- `{project-root}/_bmad/bmm/config.yaml` — bmm-specific vars

| Variable | Source file | Used For |
|----------|-------------|----------|
| `{project-root}` | runtime | All file path resolution |
| `{project_name}` | core/config.yaml *(moved from bmm in 6.6, #2348)* | Project identification |
| `{output_folder}` | core/config.yaml | Base output directory for all artifacts |
| `{user_name}` | core/config.yaml | Agent greetings and communication |
| `{communication_language}` | core/config.yaml | Agent output language |
| `{document_output_language}` | core/config.yaml | Written artifact language |
| `{planning_artifacts}` | bmm/config.yaml | Epic files, PRDs, story specs |
| `{implementation_artifacts}` | bmm/config.yaml | Sprint status, test reports, trace reports |
| `{project_knowledge}` | bmm/config.yaml | Project documentation directory |
| `{project_context}` | runtime glob *(6.8, #2422)* | `**/project-context.md` (load-if-exists) — coding standards / project-wide patterns; skills self-resolve, passed in env for completeness |
| `{user_skill_level}` | bmm/config.yaml | Agent communication complexity |

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
- project_context: {project_context}        # 6.8: **/project-context.md, load-if-exists; skills self-resolve, passed for completeness
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
- bmad_skills_root: ${BMAD_SKILLS_ROOT}     # 6.8: resolved root for BMAD skill support files (checklist.md, methods.csv, compile-epic-context.md)
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

## Token Usage Log (always on)

<token-usage-log CRITICAL="TRUE">
Every sprint produces a token-usage log — no flag, no user request needed. This is the pipeline's cost telemetry: the 2026-07-15 tuning pass (Haiku classifier, Sonnet Step 9, Step 10 fold, etc.) was only possible because three sprints of usage were captured manually; from now on the data captures itself.

Path: resolved in Phase 0 as `${TOKEN_USAGE_LOG_PATH}` = `{implementation_artifacts}/sprint-epic-${EPIC_ID}-token-usage.md`.

**Coordinator-only artifact.** Do NOT add `${TOKEN_USAGE_LOG_PATH}` to `${BMAD_ENV_BLOCK}` and do NOT mention it in any agent prompt — agents cannot observe their own usage, so including it would only add fixed prompt overhead to every spawn (the exact waste pattern this log exists to catch).

**Data source:** the harness reports each subagent's usage in the Agent tool result (`subagent_tokens`, tool-call count, wall-clock duration). Record figures EXACTLY as harness-reported — never estimate. If a figure is unobservable (e.g. a spawn killed before reporting), record what is known and note the gap.

### File header (created at Phase 0; if the file exists from a prior run for this epic, append a separator + new sprint-run header — do NOT overwrite)

```markdown
# Epic ${EPIC_ID} Sprint — Subagent Token Usage

All figures are harness-reported (`subagent_tokens` from each Agent tool result). Nothing is estimated. `subagent_tokens` is the agent's total run usage; `tools` = tool calls made; `dur` = wall-clock seconds.

Sprint: `{full invocation}` — {story list}, {sequential|parallel N}, {tier notes}.
Model key: O = Opus, S = Sonnet, H = Haiku.
```

### Logging rules (coordinator)

1. **After EVERY agent result, append a row immediately** — `| Step | Model | Tokens | Tools | Dur (s) |` under the appropriate section (`## Phase 0 (Discovery)`, `### Story ${SID} (${tier} tier)`, `### Epic-level`). This includes Phase 0 agents, retries, killed/degraded/stalled spawns, SendMessage-resumed runs (log each attempt as its own row with a parenthetical, e.g. "attempt 1 (killed: session limit)", "resumed via SendMessage"), and epic-level agents. Waste rows are data, not noise — the stall tax was the biggest hidden cost in the sprints that motivated this log.
2. **Coordinator-inline work is not agent-billed** — Step 10 YAML flips, classifier-skip overrides, and task bookkeeping have no `subagent_tokens`; do not invent numbers for them. Where a step was skipped or folded, note it in the story table (e.g. "folded into Step 7 (coordinator grep-verified)").
3. **After each story completes:** add the story's total to its section heading (sum of ALL its spawns including waste), e.g. `### Story <SID> (standard tier) — total 826,991 (incl. 62,998 wasted on 2 failed spawns)`.
4. **At sprint end, append:**
   - Cross-story step averages table: `| Step | Runs | Avg tokens | Range | Notes |` (completed runs only; one-line notes flagging trends).
   - Totals table: Phase 0 / stories / epic-level / waste (with event count and % of total) / sprint total.
   - **Trim/bulk observations** — 3–6 bullets on what this sprint's data suggests. Compare against prior sprints when available: glob `{implementation_artifacts}/sprint-epic-*-token-usage.md` (plus any older ad-hoc usage docs the project keeps under `{project_knowledge}`), and cite cross-sprint deltas (e.g. "Step 4 avg 194k → 233k").
   - A note that coordinator (orchestrator) usage is not self-observable — point the user at `/cost` or the Claude-app session view for the authoritative number.
5. **Append-only during the run** — never rewrite earlier rows (crash-safe; a dead session loses at most the current row). The sprint-end sections are the only post-hoc additions.

### Sprint Summary integration

The Sprint Summary (final output) MUST include a `### Token Usage` block: sprint total, avg/story, most expensive step (avg), waste % (event count), and the log path.
</token-usage-log>

## Input Format

```
$ARGUMENTS = <EPIC_ID> [STORY_IDS_WITH_OPTIONAL_TIER...] [--parallel N] [--tier=lite|standard|full] [--skip-elicitation] [--auto-fix]
```

A story ID may carry an explicit tier suffix using a colon: `STORY_ID:lite`, `STORY_ID:standard`, `STORY_ID:full`. A bare `STORY_ID` (no suffix) is auto-classified by the Step 1.5 classifier. The optional `--tier=` flag forces the SAME tier for every story in this run (overrides both auto-classification and any per-story suffixes; logged once to the deferred-decisions doc).

**Examples:**
- `/enhanced-automated-sprint 5` — All `ready-for-dev` + `backlog` stories in Epic 5; each auto-classified after Step 1
- `/enhanced-automated-sprint 5 5-1 5-2` — Only stories 5-1 and 5-2; both auto-classified
- `/enhanced-automated-sprint 5 --parallel 2` — Epic 5, run up to 2 stories in parallel; each auto-classified
- `/enhanced-automated-sprint 5 5-1:lite 5-2:full` — Force 5-1 to lite tier, 5-2 to full tier; the classifier is SKIPPED for overridden stories (the override + its source is logged to the deferred-decisions doc)
- `/enhanced-automated-sprint 5 --tier=full` — Force every story in Epic 5 to full tier (legacy "always run the full pipeline" behavior)
- `/enhanced-automated-sprint 5 5-1 --skip-elicitation` — Auto-classify, but unconditionally skip Step 2 even if classifier picks `full` (legacy flag, retained)

**Defaults:** `--parallel 1` (sequential), tier auto-classified per story. Unattended mode and auto-fix-Critical-and-High are now ALWAYS ON (see Decision Points below).

**Tier definitions:**

| Tier | Steps run | Steps skipped | Intended for |
|------|-----------|---------------|--------------|
| `lite` | 1, 1.5, 5, 6, 7, 8, 9, 10 | 2, 3, 4 | Trivial scope: ≤2 total impl files, single module, no new deps, no risk markers, no migrations of any kind, BMAD size XS/S |
| `standard` | 1, 1.5, 3, 4, 5, 6, 7, 8, 9, 10 | 2 | Default for most stories. Includes additive migrations (CREATE TABLE/INDEX, new RLS), threading additive changes through many existing files (mods don't trigger full), pure-function stories regardless of AC count |
| `full` | 1, 1.5, 2, 3, 4, 5, 6, 7, 8, 9, 10 | none | High-risk: auth/payments/PII/security markers, destructive migrations (DROP/ALTER-DROP/type-narrow/data-overwrite), >3 NEW files (new subsystem signal), new top-level module, new external deps, or BMAD size L/XL |

Skipped steps are still created in the task graph and marked `completed` immediately at creation time (same mechanism as `--skip-elicitation`, see Per-Story Tasks below). This keeps the dependency chain intact regardless of tier.

> **DEPRECATED:** `--auto-fix` is now the default and has no effect. The flag is accepted as a no-op for backward compatibility with saved invocations, but documented as deprecated. Auto-fix-Critical-and-High behavior is on for every run.

**Story status mapping:** BMAD 6.4 uses `ready-for-dev` as the primary status. The legacy `drafted` status is auto-mapped to `ready-for-dev` for backward compatibility. The coordinator accepts both.

**E2E tests:** Step 4 (E2E TDD) is the sole TDD step. It is blocked by Step 3 (validation) and feeds Step 5 (implementation). Unit tests are written by Amelia inside Step 5 in Kent-Beck-style red-green-refactor — BMAD 6.3+ deliberately removed the standalone unit-TDD skill when Quinn QA was consolidated into Amelia. **Tier interaction:** Step 4 only runs for `standard` and `full` tiers. For `lite`, Step 4 is auto-completed at Step 1.5 — Amelia still writes inline unit tests during Step 5, but no separate E2E red-phase exists. This is intentional: lite-tier stories are explicitly scoped to changes where E2E TDD is overkill.

**Optimization:** Worktree isolation is decided at spawn time based on **actual concurrency**, not just the `--parallel` flag:
- If `--parallel 1`: Steps 5/8 run directly on the working branch WITHOUT worktree isolation (no merge steps 6/9 needed).
- If `--parallel >= 2` but only ONE story is actually at Step 5/8 in this wave: skip worktree, run directly. No point paying worktree + merge overhead for a single concurrent implementation.
- If `--parallel >= 2` AND multiple stories reach Step 5/8 in the same wave: use `isolation: "worktree"` for each, then sequential merges via Steps 6/9.

## Phase 0: Discovery & Planning

<rules CRITICAL="TRUE">
Before ANY pipeline work begins, the coordinator MUST:

1. **Load BMAD config** — read BOTH `{project-root}/_bmad/core/config.yaml` (for `{project_name}`, `{output_folder}`, `{user_name}`, `{communication_language}`, `{document_output_language}`) AND `{project-root}/_bmad/bmm/config.yaml` (for `{planning_artifacts}`, `{implementation_artifacts}`, `{project_knowledge}`, `{user_skill_level}`). In BMAD 6.6 (#2348) `project_name` moved from bmm to core; if the install pre-dates 6.6 it may still live under bmm — read both files and prefer the core copy when both exist (the installer's auto-migration matches this precedence).
2. **Resolve verification commands** — read `CLAUDE.md` or `package.json` scripts to determine `${test_command}`, `${test_list_command}`, `${typecheck_command}`, `${build_command}`, `${lint_command}`. Fall back to defaults if not found.
3. **Determine working branch** — run `git branch --show-current` and store as `${WORKING_BRANCH}`
4. **Detect skill architecture** — check if `.claude/skills/` directory exists. If yes, set `${SKILL_ARCH}` to `skills`. If only `.claude/commands/` exists, set to `commands`. Store for agent spawn templates (affects skill invocation paths). Probe skill availability by spawning a lightweight agent that attempts `/bmad-help` — if it fails, switch all templates to inline-workflow mode (load workflow YAML directly instead of invoking `/bmad-*` skills).
4a. **Resolve `${BMAD_SKILLS_ROOT}` (6.8 path fix)** — three pipeline steps read BMAD skill *support files* by explicit path (Step 2 → `bmad-advanced-elicitation/methods.csv`, Step 3 → `bmad-create-story/checklist.md`, Phase 0 §9.3 → `bmad-quick-dev/compile-epic-context.md`). Since the 6.2 `.claude/skills/` move, these files are co-located inside each skill's own directory and the redundant `_bmad/` copies are removed by the installer. Resolve `${BMAD_SKILLS_ROOT}` by probing this fallback cascade in order and taking the FIRST directory that contains `bmad-create-story/checklist.md`:
   1. `{project-root}/.claude/skills` — canonical for 6.8 Claude Code installs
   2. `{project-root}/_bmad/bmm/workflows/4-implementation` + `{project-root}/_bmad/core/skills` — split legacy/source-style layout (bmm support files under the phase folder, core skills like advanced-elicitation under `_bmad/core/skills`); if this branch is selected, store BOTH roots and resolve each support file from whichever root contains it
   3. `{project-root}/_bmad/bmm/skills` + `{project-root}/_bmad/core/skills` — pre-6.6 layout (kept for backward compatibility)
   Store the resolved root(s) as `${BMAD_SKILLS_ROOT}` and add to `${BMAD_ENV_BLOCK}`. If none of the candidates resolve, log a `confidence: low, needs_human_review: yes` entry to the deferred-decisions log (once it exists) and fall back to `.claude/skills` — the `/bmad-*` skill invocations in Steps 1/4/5/7 do NOT depend on this root (they resolve their own support files internally); only the three explicit-path reads do.
5. **Resolve `${ANTI_LEAK_BLOCK}`** — copy the static text from the "Codebase Anti-Leak Block (HARD CONSTRAINT)" section above into a single string. No variables to substitute. Store for injection into Steps 5, 6, 8, 9 prompts.
6. **Build `${BMAD_ENV_BLOCK}`** — expand the Agent Environment Block template with all resolved values (including `${EPIC_CONTEXT_PATH}` and `${DEFERRED_DECISIONS_PATH}` once resolved in steps 9–10 below). This block is injected into every agent prompt for the rest of the pipeline.
7. **Parse `$ARGUMENTS`** — extract EPIC_ID, optional STORY_IDS (each potentially carrying a `:lite|:standard|:full` tier suffix — strip and store as `${TIER_HINT[SID]}`), and flags. (`--auto-fix` is a no-op; record but ignore.) If `--tier=` is set, store as `${GLOBAL_TIER}` — this forces every story to that tier and overrides any per-story `:tier` suffix. Validate: tier values must be one of `lite|standard|full`; reject the run with a clear error otherwise.
8. **Read sprint-status.yaml** at `{implementation_artifacts}/sprint-status.yaml`
9. **Compile or reuse epic context.**
   1. Look for cached file: `{implementation_artifacts}/epic-${EPIC_ID}-context.md`. Validity criteria: file exists, non-empty, starts with `# Epic ${EPIC_ID} Context:`, AND no file in `{planning_artifacts}` is newer (`mtime` comparison).
   2. If valid: store its path as `${EPIC_CONTEXT_PATH}` and proceed.
   3. If missing or stale: spawn a single sub-agent (`subagent_type: general-purpose`, `model: sonnet`) whose prompt instructs it to read `${BMAD_SKILLS_ROOT}/bmad-quick-dev/compile-epic-context.md` (6.8: resolved in step 4a — canonical `.claude/skills/bmad-quick-dev/compile-epic-context.md`) and execute it against `${EPIC_ID}`, writing output to `{implementation_artifacts}/epic-${EPIC_ID}-context.md`. Do NOT inline the prompt — reference the BMAD file by path. Capture the path as `${EPIC_CONTEXT_PATH}`.
   4. Add `${EPIC_CONTEXT_PATH}` to `${BMAD_ENV_BLOCK}` so every downstream agent receives it.
   5. **Mid-epic recompile rule:** the cache also goes stale as stories COMPLETE — predecessor context accumulates in the planning artifacts and Step 1 create-story cost grows with it (+68–85% within-sprint growth measured in two consecutive sprints). After every 3rd completed story in this run, recompile the cache (same sub-agent as §9.3) before the next story's Step 1. Validated in practice: create-story cost dropped ~40% (224k → 138k) immediately after a mid-sprint recompile.
10. **Initialize deferred-decisions log.**
   1. Resolve `${DEFERRED_DECISIONS_PATH}` = `{implementation_artifacts}/sprint-epic-${EPIC_ID}-deferred-decisions.md`.
   2. If file does not exist: create with header `# Sprint Deferred Decisions — Epic ${EPIC_ID}\n\nSprint started: {ISO timestamp}\n\n`.
   3. If file already exists (prior run for this epic): append a separator + a new sprint-run header (do NOT overwrite).
   4. Add `${DEFERRED_DECISIONS_PATH}` to `${BMAD_ENV_BLOCK}` so every downstream agent can append entries.
10a. **Initialize token-usage log.** Resolve `${TOKEN_USAGE_LOG_PATH}` = `{implementation_artifacts}/sprint-epic-${EPIC_ID}-token-usage.md`; create with the documented header (or append a new sprint-run header if it exists — same convention as the deferred-decisions log). Coordinator-only: do NOT add to `${BMAD_ENV_BLOCK}` (see Token Usage Log section). Log Phase 0's own agents (epic-context compile, skill probe) as its first rows.
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

## Story Tier Classification (Step 1.5)

<rules CRITICAL="TRUE">
Tier classification runs **per story, immediately after Step 1 (Create Story) completes**, and **before Step 2 is unblocked**. The classifier reads the just-created story file and emits one of `lite | standard | full`. The result determines which downstream tasks are auto-completed at creation time (see Per-Story Tasks below).

This is a rubric-matching task — keyword scanning and counting, no design judgment — so it runs on **Haiku with a slim prompt** (no `${BMAD_ENV_BLOCK}`; the coordinator passes the two file paths it needs directly). Measured across 22 stories: the Sonnet version cost a flat ~48k/story, ~90% of it fixed prompt overhead, for a one-word answer.

### Resolution order (highest priority first)

1. `${GLOBAL_TIER}` (from `--tier=` flag) — forces tier for every story in the run.
2. `${TIER_HINT[SID]}` (from `STORY_ID:tier` suffix) — forces tier for this specific story.
3. **Auto-classification** — Haiku classifier output.

When 1 or 2 applies, the classifier is **SKIPPED entirely** — no agent spawn. The coordinator logs the override (chosen tier + source) to `${DEFERRED_DECISIONS_PATH}` and immediately auto-completes the skipped tasks. (The prior always-run-for-visibility rule cost ~48k/story for log-only output; if an epic is obviously uniform — e.g. all billing stories — pass `--tier=full` and pay zero classifier cost.)

### Classifier agent spec

```
Task tool:
  description: "[${SID}] Classify story tier"
  subagent_type: general-purpose
  model: haiku
  prompt: |
    You are classifying story ${SID} into a pipeline tier. This is a rubric-matching task:
    keyword scanning and counting only — no design judgment, no speculation.

    Read ONLY:
    - The story file at ${STORY_FILE_PATH}   (exact path from Step 1's return — do not search for it)
    - ${EPIC_CONTEXT_PATH} ONLY IF the story file is missing a File List or size estimate

    Apply the rubric below and emit a single JSON object on the FINAL line of your response. No prose after the JSON.

    Rubric (assign tier by FIRST matching row, top to bottom):

    | Tier | Trigger conditions (any one is sufficient) |
    |------|--------------------------------------------|
    | full | High-risk markers in story title/ACs/tasks: auth, authn/authz, password, token, session, payment, billing, money, PCI, PII, GDPR, public API, breaking change, security, crypto, RBAC. OR: **destructive migration** (DROP TABLE/COLUMN/INDEX, ALTER...DROP, type narrowing, adding NOT NULL to existing column, RENAME, data backfill that overwrites). OR: **>3 NEW implementation files** (signals a new subsystem or significant new surface area; modifying many existing files does NOT trigger this — threading an additive change through an established system stays at standard). OR: introduces a new top-level module/package. OR: adds a new external dependency (npm/pip/go/cargo/etc.). OR: BMAD size estimate is L or XL. |
    | lite | All of: ≤2 total implementation files in the File List (created + modified, excluding tests/docs) AND single module/package scope AND no new deps AND no risk markers (high-risk OR migration of any kind) AND BMAD size estimate is XS or S AND story type is one of {bug-fix, copy-tweak, config-change, refactor-localized, doc-only, dependency-bump-patch}. |
    | standard | Everything else (the safe default — preserves validation + E2E TDD, drops only advanced elicitation). Includes: **additive migrations** (CREATE TABLE, CREATE INDEX, additive ALTER, new RLS policies on new tables), single-feature implementations across 3-6 files, well-specified pure-function stories regardless of AC count. |

    **Note on AC count:** AC count is NOT a tier trigger. BMAD stories often have 15-20 ACs even when scope is narrow because the methodology encourages exhaustive criteria. Use file-list size and risk markers as the real complexity signal, not AC count.

    **Note on additive vs destructive migrations:** A migration that only adds new tables/columns/indexes with no data movement on existing rows is `standard`. A migration that mutates existing data, drops anything, or narrows types is `full` — the rollback surface is fundamentally different.

    Emit EXACTLY this JSON shape:
    {"tier": "lite|standard|full", "confidence": "high|medium|low", "reasoning": "<one sentence citing the rubric row>", "signals": {"ac_count": <int>, "risk_markers": [<strings>], "migration_kind": "none|additive|destructive", "new_file_count_estimate": <int>, "modified_file_count_estimate": <int>, "new_deps": <bool>, "size": "<XS|S|M|L|XL|unknown>"}}

    Confidence guide:
    - high: rubric trigger is unambiguous (e.g. story title says "add OAuth login" → full)
    - medium: borderline (e.g. 4 ACs, no risk markers — could be standard or full)
    - low: story file is sparse, signals unclear; default to standard and flag medium-low confidence

    Do NOT speculate beyond the story file and epic context. Do NOT read source code.
```

### Coordinator handling of classifier output

**Override path (no classifier ran):** append an entry to `${DEFERRED_DECISIONS_PATH}` with the chosen tier, source (`global-flag | per-story-suffix`), `confidence: high, needs_human_review: no`, and the note "classifier skipped (override)". Then jump to auto-completion (step 4 below).

**Auto path** — after the classifier returns:

1. Resolve `${TIER[SID]}` = classifier output, subject to the guards in steps 2–3.
2. Append an entry to `${DEFERRED_DECISIONS_PATH}` with: chosen tier, source `auto`, classifier recommendation, classifier confidence, classifier reasoning.
3. Confidence guards:
   - If confidence is `low`: choose `standard` (safe default), log `confidence: low, needs_human_review: yes`.
   - **Haiku guard:** if the recommendation is `lite` with confidence below `high`: choose `standard` instead and log it. Under-classification (skipping validation/E2E on a story that needed them) is the only costly error direction; a borderline `standard`-vs-`full` call is cheap because Step 7's consolidated review still runs on every tier.
4. **Auto-complete skipped tasks immediately** — using TaskUpdate, mark the appropriate per-story tasks as `completed`:
   - tier = `lite`: complete Steps 2, 3, 4 (in addition to any tasks the classifier just unblocked)
   - tier = `standard`: complete Step 2 only
   - tier = `full`: complete nothing extra

This auto-completion uses the exact same mechanism as `--skip-elicitation` (see Per-Story Tasks Note below) — the dependency chain stays intact because Step 5 still blocks on Step 4, which is now `completed` with no work performed.

### Failure handling

If the classifier agent fails or returns malformed JSON: log `confidence: low, needs_human_review: yes` to `${DEFERRED_DECISIONS_PATH}`, default to tier `standard`, and proceed. Do NOT retry the classifier — it is a sub-second decision and a retry rarely helps; the safe default keeps the sprint moving.

### Concurrency

Step 1.5 is **PARALLEL** across stories — the classifier is read-only and story-scoped. It runs in the same wave as other unblocked Step 1.5 tasks. See the wave-based execution loop below; Step 1.5 sits between Step 1 and Step 2 in the dependency graph.
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
| `[${SID}] Step 1.5: Classify tier` | `Classifying tier for ${SID}` | `[${SID}] Step 1: Create story` |
| `[${SID}] Step 2: Advanced elicitation` | `Running elicitation on ${SID}` | `[${SID}] Step 1.5: Classify tier` |
| `[${SID}] Step 3: Validate story` | `Validating story ${SID}` | `[${SID}] Step 2: Advanced elicitation` |
| `[${SID}] Step 4: TDD E2E test generation` | `Generating TDD E2E tests for ${SID}` | `[${SID}] Step 3: Validate story` |
| `[${SID}] Step 5: Implementation` | `Implementing story ${SID}` | `[${SID}] Step 4: TDD E2E test generation` |
| `[${SID}] Step 6: Merge implementation` | `Merging ${SID} implementation to main branch` | `[${SID}] Step 5: Implementation` |
| `[${SID}] Step 7: Consolidated code review` | `Reviewing code for ${SID}` | `[${SID}] Step 6: Merge implementation` |
| `[${SID}] Step 8: Fix action items` | `Fixing review items for ${SID}` | `[${SID}] Step 7: Consolidated code review` |
| `[${SID}] Step 9: Merge fixes` | `Merging ${SID} review fixes to main branch` | `[${SID}] Step 8: Fix action items` |
| `[${SID}] Step 10: Update sprint status` | `Updating sprint status for ${SID}` | `[${SID}] Step 9: Merge fixes` |

**\*** Coordinator sets Step 1 `blockedBy` dynamically: no blocker in parallel mode, previous story's Step 10 in sequential mode (`--parallel 1`), or inter-story dependency's Step 10 if epic defines one.

**Per-Story Tasks Note (skip mechanism):** The task graph above is created in full for EVERY story regardless of tier or `--skip-elicitation`. After Step 1.5 classifies the story (or if `--skip-elicitation` is set), the coordinator marks the appropriate skipped tasks as `completed` IMMEDIATELY via TaskUpdate without spawning an agent. This avoids conditional task-graph construction — downstream tasks still block on their predecessors, but those predecessors are already done.

Skip rules (applied additively):
- tier = `lite` → Steps 2, 3, 4 marked `completed` immediately after Step 1.5
- tier = `standard` → Step 2 marked `completed` immediately after Step 1.5
- tier = `full` → no extra completions
- `--skip-elicitation` flag (legacy) → Step 2 marked `completed` regardless of tier (same effect on lite/standard, no-op on full)

### Cross-Story Dependencies

- **Sequential mode** (`--parallel 1`): Story B's Step 1 is blocked by Story A's Step 10
- **Parallel mode** (`--parallel N`): No cross-story `blockedBy` for independent stories — the **coordinator** enforces parallelism limits and merge gates (Steps 6, 9) at spawn time, NOT via task dependencies. This keeps the task graph simple and avoids false blocking.
  - Exception: Stories WITH inter-story dependencies (noted in epic file) DO get `blockedBy` on their dependency's Step 10.
- **Worktree isolation** (Steps 5, 8): These steps run in git worktrees (`isolation: "worktree"`), so they CAN run in parallel across stories. Each agent gets its own repo copy — no file conflicts during implementation.
- **Merge gates** (Steps 6, 9): After worktree work completes, the **BMAD Dev Agent (Amelia — Senior Software Engineer)** integrates the worktree branch back to the working branch. Merges run SEQUENTIALLY (one at a time) to avoid merge race conditions. Amelia resolves conflicts with senior-level judgment, verifies all tests pass post-merge, and speaks in file paths and AC IDs — no fluff. Step 9 additionally performs the per-story auto-commit sequence (see Step 9 template).

### Epic-Level Tasks

| Task Subject | ActiveForm | Blocked By |
|---|---|---|
| `[Epic ${EPIC_ID}] Sprint-status reconcile` | `Reconciling sprint-status.yaml via /bmad-sprint-status` | All stories' Step 10 |
| `[Epic ${EPIC_ID}] Cross-story integration check` | `Running cross-story integration verification` | All stories' Step 10 |
| `[Epic ${EPIC_ID}] Sprint summary` | `Generating sprint summary` | `[Epic ${EPIC_ID}] Cross-story integration check` + `[Epic ${EPIC_ID}] Sprint-status reconcile` |

**Sprint-status reconcile** is the sprint's ONE `/bmad-sprint-status` delegation (Sonnet agent). Per-story Step 10 updates are coordinator-inline YAML edits (see Step 10 template); this close-out run validates and normalizes them, updates epic-level status, and catches anything the inline edits missed. It can run in the same wave as the integration check (different files).

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
   - Steps 1, 1.5, 2, 3 (story creation / tier classification / elicitation / validation): **PARALLEL** — no shared files. Step 1.5 is read-only Haiku classification (skipped entirely when the tier is overridden).
   - Step 4 (TDD E2E): **PARALLEL** — safe because E2E test files are story-scoped. Each agent writes only to its own story's E2E test files. If stories share a test file, fall back to SEQUENTIAL for Step 4.
   - Step 5 (implementation): **PARALLEL in worktrees** — `isolation: "worktree"` gives each agent its own repo copy
   - Steps 6, 9 (merges): **SEQUENTIAL** — merge one worktree branch at a time to avoid race conditions; Step 9 also performs auto-commit
   - Step 7 (consolidated review): **PARALLEL** — read-only analysis. BMAD 6.4 runs Blind Hunter, Edge Case Hunter, and Acceptance Auditor internally within a single `/bmad-code-review` invocation.
   - Step 8 (fixes): **PARALLEL in worktrees** — same worktree isolation as Step 5
   - Step 10: **COORDINATOR-INLINE** — the coordinator itself edits the story's entry in `sprint-status.yaml` (status-field flip + grep verify), one story at a time. No agent spawn. Two concurrent writes to the same YAML file = data loss.
4. **Spawn agents for ALL parallelizable unblocked tasks in a SINGLE message** — this is how Claude Code runs agents concurrently. Multiple Task tool calls in one response = true parallelism.
5. **Wait for all spawned agents to complete**
6. **Mark completed tasks, report results, loop back to step 1**

### Parallelism Example

Given stories A-1 (classified `full`) and A-2 (classified `lite`) with `--parallel 2` and no inter-story dependencies:

```
Wave 1:  [A-1] Step 1   + [A-2] Step 1               parallel (story creation)
Wave 2:  [A-1] Step 1.5 + [A-2] Step 1.5             parallel (tier classification)
                                                      → A-2 Steps 2, 3, 4 marked completed (lite tier)
Wave 3:  [A-1] Step 2                                 parallel (A-2 has no work this wave)
Wave 4:  [A-1] Step 3                                 parallel (A-2 still skipping)
Wave 5:  [A-1] Step 4   + [A-2] Step 5 (worktree)    A-2 races ahead — it's already at implement
Wave 6:  [A-1] Step 5 (worktree)                     A-1 catches up
Wave 7:  [A-2] Step 6                                 SEQUENTIAL merge
Wave 8:  [A-1] Step 6                                 SEQUENTIAL merge
Wave 9:  [A-1] Step 7 + [A-2] Step 7                 parallel (consolidated review)
Wave 10: [A-1] Step 8 + [A-2] Step 8 (worktrees)     parallel (fixes)
Wave 11: [A-1] Step 9                                 SEQUENTIAL merge + auto-commit
Wave 12: [A-2] Step 9                                 SEQUENTIAL merge + auto-commit
Wave 13: [A-1] Step 10, then [A-2] Step 10           COORDINATOR-INLINE (no agent spawn)
```

**Tier-aware throughput:** Lite stories burn through 2/3/4 instantly (TaskUpdate-only, no agent spawn) and reach Step 5 in the same wave a `full` peer is still on Step 4. The `--parallel N` cap on concurrent worktrees is still respected — lite stories just fill the wave faster. If all stories in a run are `lite`, the wave count collapses dramatically (no Steps 2/3/4 agents at all).

**Speedup:** Original full-tier baseline was 12 waves vs ~18+ sequential steps. BMAD 6.4's consolidated review (Blind Hunter + Edge Case Hunter + Acceptance Auditor in a single invocation) replaces the 3 separate review agents from prior versions. Implementation (the longest step) runs concurrently across stories. Lite-tier stories save 3 sequential agent spawns per story (elicitation + validation + E2E TDD) and the context they would have consumed.

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
| Step 9: Merge fixes + auto-commit | Merge worktree branch from Step 8 into working branch, then auto-commit (submodule-first, then main repo, anti-leak applied) | **BMAD Dev Agent (Amelia)** — Sonnet |

All other steps parallelize freely because they either:
- Write to story-specific files (Steps 1, 2, 4)
- Run in isolated worktrees (Steps 5, 8)
- Are read-only analysis (Steps 3, 7)

Step 10 is a coordinator-inline `sprint-status.yaml` edit, one story at a time (shared file); a single `/bmad-sprint-status` reconcile agent runs once at epic close-out.
</parallel-execution>

## Execution Rules

<rules CRITICAL="TRUE">
1. **Act as COORDINATOR** — delegate all work via Task tool agents, do NOT execute pipeline steps yourself
2. **One agent per step** — each step spawns a focused Task agent. Do NOT pass full conversation history. DO pass `${BMAD_ENV_BLOCK}` to every agent — environment variables are configuration, not history. For Steps 5, 6, 8, 9 ALSO prepend `${ANTI_LEAK_BLOCK}` immediately after `${BMAD_ENV_BLOCK}`.
3. **PARALLEL by default** — when multiple tasks are unblocked AND parallelizable (see Sequential Gate Rules above), spawn them ALL in a single message. This is the core performance advantage of the enhanced pipeline.
4. **TaskUpdate before and after** — mark task `in_progress` BEFORE spawning the agent, mark `completed` AFTER agent succeeds
4a. **Log token usage after EVERY agent result** — append the harness-reported `subagent_tokens` / tool count / duration row to `${TOKEN_USAGE_LOG_PATH}` per the Token Usage Log rules (retries, killed/degraded spawns, and resumes included). This is always on.
5. **TaskList after each wave** — check what's unblocked next
6. **Failure stops the STORY, not the sprint** — on step failure: log to `${DEFERRED_DECISIONS_PATH}` and retry once with the same agent. On second failure, mark the story `blocked`, log a follow-up entry, and continue with other independent stories.
7. **Context budget per agent:** Each agent should read at most 5-8 files. If a step needs more context, break it into sub-agents.
8. **Steps 8 + 9 are conditional** — only create a fix agent if Step 7 produced action items. If Step 7 (consolidated review) reports no action items, mark BOTH 8 AND 9 as completed immediately and proceed to Step 10. If Step 7 produced ONLY Medium/Low items (which are deferred to the log), also mark 8 + 9 completed and proceed to Step 10.
8a. **Tasks/Subtasks validation gate** — after Step 5 completes, the coordinator MUST check the agent's return for "Tasks/Subtasks completion". If the agent reports incomplete tasks or does NOT confirm story file was updated, the coordinator logs a `confidence: low, needs_human_review: yes` entry to `${DEFERRED_DECISIONS_PATH}` and proceeds (does not pause). The story file's `## Tasks / Subtasks` section is the source of truth for implementation completeness — test results alone are NOT sufficient.
9. **Step 10 is coordinator-inline** — the coordinator updates sprint-status.yaml itself (flip story ${SID} to its final status, grep-verify the edit), one story at a time. Do NOT spawn a per-story agent for this — the dedicated agent measured 52–71k tokens/story for a one-line YAML flip, and the inline fold was proven mid-sprint on two stories with no quality loss. A single `/bmad-sprint-status` reconcile agent runs ONCE at epic close-out (see Epic-Level Tasks).
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

    INPUT CAP (token discipline — this step's cost grew 50% across three epics purely from
    re-reading ever-larger story files, not from more method work):
    Read ONLY these story-file sections: the header (Status / Story / description), 
    "## Acceptance Criteria", and "## Tasks / Subtasks". Do NOT read "## Dev Notes" or any
    pasted reference/architecture excerpts up front — technical grounding comes from
    ${EPIC_CONTEXT_PATH} (already distilled). If a selected method genuinely needs a specific
    technical detail the epic context lacks, read just that one Dev Notes subsection.
    Apply your enhancements as targeted edits to those sections — do NOT rewrite the whole file.

    1. Read the capped sections of the story file at: ${STORY_FILE_PATH} (per INPUT CAP above),
       plus ${EPIC_CONTEXT_PATH}
    2. Read methods CSV at: ${BMAD_SKILLS_ROOT}/bmad-advanced-elicitation/methods.csv
       (6.8: canonical `.claude/skills/bmad-advanced-elicitation/methods.csv`; resolved in Phase 0 step 4a. NOTE: 6.8 added a `framing` category + 19 new techniques, all 50 prior methods preserved — selection logic is unaffected.)
    3. Auto-select the 3 methods most relevant to this story's context
    4. Apply each method in sequence to enhance the story
    5. Save the enhanced story sections back to ${STORY_FILE_PATH} via targeted edits (leave Dev Notes and other unread sections untouched)
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
  model: sonnet
  prompt: |
    ${BMAD_ENV_BLOCK}

    You are an independent quality validator running in a FRESH CONTEXT. Your job is to execute
    BMAD's authoritative story-validation checklist against story ${SID}.

    1. Read and follow the checklist at:
       ${BMAD_SKILLS_ROOT}/bmad-create-story/checklist.md
       (6.8: canonical `.claude/skills/bmad-create-story/checklist.md`; resolved in Phase 0 step 4a.)
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
  model: opus
  isolation: "worktree"          <- agent gets its own repo copy (only when parallel)
  prompt: |
    ${BMAD_ENV_BLOCK}
    ${ANTI_LEAK_BLOCK}

    Implement story ${SID} by following the story file's Tasks/Subtasks section.
    Execute: /bmad-dev-story ${SID} yolo

    Pre-compiled epic context: ${EPIC_CONTEXT_PATH} — load this BEFORE the epic file; it is the distilled, scope-aggressive view of the epic.
    Story file: ${STORY_FILE_PATH}
    E2E test files: ${E2E_TEST_FILE_PATHS}

    BASELINE_COMMIT (6.8, #2403):
    On its first run for a ready-for-dev story, /bmad-dev-story stamps `baseline_commit: <git rev-parse HEAD>`
    into the story file's YAML frontmatter (it preserves any existing value). You are running inside a git
    WORKTREE, so HEAD here is the working-branch tip at spawn time — that is the correct, intended baseline.
    Do NOT hand-edit or remove `baseline_commit`. The story file lives under _bmad-output/ (gitignored), so
    this value persists through the Step 6 merge and is read by /bmad-code-review in Step 7 as its diff base.

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

    REVIEW SCOPE — CONSTRAIN TO THIS STORY (6.8, baseline_commit interaction):
    /bmad-code-review step-01 reads `baseline_commit` from the story frontmatter and uses it as the
    diff baseline (`git diff baseline_commit..HEAD`). That baseline was captured in Step 5's worktree at
    spawn time. In parallel/sequential runs, SIBLING stories may have merged into ${WORKING_BRANCH}
    between that spawn and now — so a raw baseline diff would over-scope this review to include other
    stories' changes. To prevent cross-story contamination:
    - Treat the File List above (${IMPL_FILE_PATHS} + ${TEST_FILE_PATHS}) as the AUTHORITATIVE review
      scope. Review ONLY those paths.
    - If baseline_commit yields files NOT in this story's File List, EXCLUDE them — they belong to a
      sibling story and are out of scope for ${SID}'s review.
    - The `yolo` flag suppresses code-review's interactive HALTs (branch-confirm in step-01,
      pre-review summary confirmation); proceed unattended. baseline_commit additionally gives a
      deterministic baseline so the branch-confirm prompt is not reached.

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

**Coordinator liveness protocol (Step 7) — CRITICAL:** Review is the pipeline's most stall-prone step (four incidents across the three measured sprints; the stall tax outgrew every per-step cost). Two rules:

1. **Nudge before respawn.** If a Step 7 agent has gone silent well past its normal envelope (clean reviews finish in ~4–15 min), send it a SendMessage nudge ("continue the review; if the Acceptance Auditor pass hasn't run yet, run it now and return the consolidated findings") instead of killing and respawning. Resuming a stalled reviewer worked in three separate measured incidents and costs a fraction of a fresh ~130k spawn. A respawn (only if the nudge fails) counts as the one retry under Decision Point #5.
2. **Collect late child findings before committing.** If the review parent spawned internal hunter sub-agents and stalled or died before consolidating them, the coordinator MUST collect those children's findings and route them through the normal severity triage BEFORE Step 9's auto-commit runs. In one measured incident, late-delivered child reports contained a real HIGH finding that had to be fixed post-commit. Step 9 must never commit while review child findings are outstanding.

#### Step 8: Fix Action Items (Conditional, Worktree Isolated)
```
Task tool:
  description: "[${SID}] Fix review items"
  subagent_type: general-purpose
  model: opus
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
- **`model: sonnet`** (NOT opus — 22 stories of data show this step is pure git mechanics averaging 31–43k with zero judgment-requiring conflicts; leak scrubs are grep-driven. The ambiguous-conflict hard pause in the merge protocol remains the escape hatch: Sonnet detects ambiguity and STOPS, it doesn't resolve it)
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
     - **Do NOT mention the docs submodule** (or any submodule pointer bump) in the
       main-repo commit message. The submodule pointer is staging-level mechanics, not
       a user-facing change. The message describes ONLY the code/feature change.
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

#### Step 10: Update Sprint Status (Coordinator-Inline — NO agent spawn)
```
The coordinator performs this itself, one story at a time (shared sprint-status.yaml file):
1. Translate Step 9's return contract (or Step 7's, when 8/9 were skipped) into the story's
   final status.
2. Edit {implementation_artifacts}/sprint-status.yaml directly: flip story ${SID}'s status
   field (and any per-story fields the file tracks, e.g. commit SHA).
3. Grep-verify the edit landed (`grep -A2 "${SID}" sprint-status.yaml`).
4. Mark the Step 10 task completed.

Epic close-out: after ALL stories' Step 10 are done, ONE /bmad-sprint-status reconcile agent
runs (see Epic-Level Tasks) to validate/normalize the inline edits and close out epic-level
status. This replaces N per-story agents (52–71k each) with one ~60k run per sprint.
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

3. **Step 3 (validate) FAIL handling:** Auto-correct + log + block-on-second-fail. On first FAIL, spawn one corrective sub-agent (Sonnet, `subagent_type: general-purpose`) that reads the FAIL findings + the story file + the epic file, applies fixes for Critical-tier findings to the story file, and re-runs the BMAD checklist. If the second run still FAILs: mark the story `blocked`, append a `confidence: low, needs_human_review: yes` entry to `${DEFERRED_DECISIONS_PATH}`, and continue with other stories in the sprint. (Never an infinite retry loop — exactly one auto-correction pass.)

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
- **Step 7 review stall:** apply the Step 7 coordinator liveness protocol — SendMessage nudge first; respawn only if the nudge fails (that respawn is the one retry per Decision Point #5). Never run Step 9's auto-commit while review child-agent findings are outstanding.
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

### Token Usage
- Sprint total (subagents only): [tokens]
- Avg per story: [tokens] | Most expensive step: [step] ([avg])
- Waste: [tokens] ([N] events, [%] of total)
- Full log: ${TOKEN_USAGE_LOG_PATH}
- Coordinator usage not included — check /cost for the session total.

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
| Step 1.5: Classify tier | **haiku** | — | Rubric keyword-scan + counting; slim prompt (no env block); skipped entirely on tier override. Guard: `lite` below high confidence promotes to `standard` |
| Step 2: Elicitation | opus | — | Method selection requires nuanced judgment; input capped to description + ACs + Tasks/Subtasks + epic-context cache |
| Step 3: Validate (BMAD checklist runner) | sonnet | — | Mechanical 8-step checklist execution against the story spec; sonnet is the second opinion (different model from Step 1 opus = real diversity), and checklist work doesn't need opus reasoning |
| Step 4: TDD E2E | sonnet | — | E2E test generation from ACs, speed matters |
| Step 5: Implementation | opus | **worktree** | Longest step, worktree enables parallel execution across stories; Amelia writes Kent-Beck-style unit tests inline |
| Step 6: Merge impl | **opus** | — | **BMAD Dev Agent (Amelia)** — senior engineer merge judgment, conflict resolution, post-merge verification (NO auto-commit) |
| Step 7: Consolidated review | opus | — | BMAD 6.4 runs Blind Hunter + Edge Case Hunter + Acceptance Auditor internally; Acceptance Auditor's per-AC verdict supplants the dropped AC-trace step |
| Step 8: Fixes | opus | **worktree** | Targeted fixes for Critical/High items in isolation, parallelizable across stories |
| Step 9: Merge fixes + auto-commit | **sonnet** | — | **BMAD Dev Agent (Amelia)** — same merge protocol as Step 6 PLUS the per-story auto-commit sequence. Downgraded from opus: 22/22 stories were pure git mechanics; ambiguous conflicts still hard-pause |
| Step 10: Sprint status | coordinator | — | Coordinator-inline YAML edit + grep verify per story; ONE `/bmad-sprint-status` reconcile agent (sonnet) at epic close-out |
