# BMAD-OVERRIDE-CLAUDE-SCRIPTS

Various scripts to make your life easier with BMAD for Claude Code.

## Version Compatibility

Scripts are organized by exact BMAD version. The installer auto-detects your BMAD version and picks the right one.

| Folder  | BMAD Version | Scripts                                                   | Notes |
|---------|-------------|-----------------------------------------------------------|-------|
| `6.0.3` | 6.0.3       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Tasks/Subtasks fix |
| `6.0.4` | 6.0.4       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Same scripts — core workflows unchanged |
| `6.2.0` | 6.2.0       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Consolidated review, E2E TDD, `.claude/skills/` |
| `6.4.0` | 6.4.0       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Skill renames, 9-step pipeline, unattended-by-default, anti-leak commits, auto-commit (incl. submodules), deferred-decisions log, epic-context cache |
| `6.6.0` | 6.6.0       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | `project_name` → `core/config.yaml` (#2348); tier-adaptive pipeline (lite/standard/full classifier) |
| `6.8.0` | 6.8.0       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | `.claude/skills/` support-file path fix (`${BMAD_SKILLS_ROOT}`); `baseline_commit` review-scope guard (#2403); `project_context` (#2422); token-data tuning (Haiku classifier, Sonnet Step 9, Step 10 fold); always-on token-usage log |

Root-level files are kept as a fallback for the latest version.

> **Note:** No `6.3.0/`, `6.5.0/`, or `6.7.0/` folder is shipped — those users fall through the compatibility chain to the nearest lower version (6.3.x → `6.2.0`, 6.5.x → `6.4.0`, 6.7.x → `6.6.0`). This fork is personal and the user runs the latest BMAD directly.

### BMAD 6.2 Architecture Change

BMAD 6.2 replaces `.claude/commands/` with `.claude/skills/` (using `SKILL.md` entry points). The installer auto-detects the architecture and installs to the correct location:
- **BMAD 6.2+**: `.claude/skills/enhanced-automated-sprint/SKILL.md`
- **Pre-6.2**: `.claude/commands/enhanced-automated-sprint.md`

Key changes in the 6.2.0 pipeline:
- **Consolidated review**: `/bmad-bmm-code-review` now runs Blind Hunter + Edge Case Hunter + Acceptance Auditor internally (Steps 7+8+8b collapsed into Step 7)
- **E2E TDD**: Step 4b generates failing E2E tests in parallel with unit TDD, using `/bmad-qa-generate-e2e-tests`
- **Story status**: `ready-for-dev` replaces `drafted` (legacy status auto-mapped)

### What's new in 6.4.0

This is a personal fork; the new behaviors below are baked-in **defaults with no opt-out flags**. There is no backward-compat surface to preserve — if a default ever needs to change, the script is the source of truth.

- **Skill renames** — every `/bmad-bmm-*` invocation rewritten to `/bmad-*` (BMAD 6.3.0 dropped the `bmm-` prefix when Quinn QA, Bob SM, and Barry quick-flow were consolidated into Amelia / `bmad-dev`).
- **Pipeline restructured: 11 → 9 steps.** Step 4 unit-TDD dropped (Amelia writes Kent-Beck-style unit tests inline in `bmad-dev-story`). Step 10 AC-trace dropped (Acceptance Auditor inside Step 7 already covers it). Step 3 redesigned as a fresh-context Opus runner that executes BMAD's authoritative `bmad-create-story/checklist.md` instead of self-validating.
- **Phase 0 epic-context cache** — compiled once at sprint kickoff via `bmad-quick-dev/compile-epic-context.md` and reused across Steps 1, 5, 7. Staleness check regenerates if any planning artifact is newer.
- **Codebase anti-leak rules (HARD CONSTRAINT)** — story IDs, AC numbers, epic refs, and the literal "BMAD" never appear in checked-in code surfaces or main-repo commit messages. Submodule commits and `_bmad-output/` artifacts are exempt.
- **Auto-commit per story at Step 9** — Amelia commits dirty submodules first (those messages MAY reference BMAD), then commits the main repo with an anti-leak-compliant message generated from `git diff --staged`. **Never auto-pushes** — push is a shared-state action and stays manual.
- **Deferred-decisions log** — every former pause point now logs to `{implementation_artifacts}/sprint-epic-${EPIC_ID}-deferred-decisions.md` instead of asking. The user reviews the log post-sprint and resolves anything flagged `needs_human_review: yes` before pushing.
- **Unattended by default** — only ambiguous merge conflicts (Step 6 / Step 9) cause a hard pause. Step failures retry once then block the story (not the sprint). The `--auto-fix` flag is now a no-op (kept for muscle-memory compatibility).

### What's new in 6.6.0

- **Config-source split (#2348)** — `project_name` moved from `_bmad/bmm/config.yaml` to `_bmad/core/config.yaml` (auto-migrated on upgrade). Phase 0 reads both files and prefers the `core` copy when both exist.
- **Tier-adaptive pipeline** — a Sonnet classifier (Step 1.5) assigns each story a tier (`lite` / `standard` / `full`) that decides which downstream steps run. `lite` skips elicitation/validation/E2E TDD; `standard` (the default) skips only elicitation; `full` runs everything. New `STORY_ID:tier` suffix and global `--tier=` flag override the classifier (its recommendation is still logged). Tier is driven by File-List size and risk markers, not AC count.

### What's new in 6.8.0

The pipeline **interface is unchanged 6.6 → 6.8** — no skill renames, same command names, same story-status vocabulary. No document conversion is required for the pipeline's inputs (stories, epics, `sprint-status.yaml`, and PRDs are all forward-compatible). The 6.8 breaking changes — `bmad-create-ux-design` → `bmad-ux` (two-spine `DESIGN.md` + `EXPERIENCE.md`) and `bmad-distillator` → `bmad-spec` — are planning surfaces the sprint does not consume.

- **`.claude/skills/` support-file path fix** — three steps read BMAD skill *support files* by explicit path (Step 2 `methods.csv`, Step 3 `create-story/checklist.md`, Phase 0 `compile-epic-context.md`). Since the 6.2 `.claude/skills/` move, those files live inside each skill's own directory and the redundant `_bmad/` copies are removed by the installer. Phase 0 now resolves `${BMAD_SKILLS_ROOT}` via a fallback cascade (`.claude/skills/` → legacy `_bmad/` layouts) and all three reads go through it. The old `_bmad/bmm/skills/` and `_bmad/core/workflows/` paths were stale.
- **`baseline_commit` review-scope guard (#2403)** — `/bmad-dev-story` now stamps `baseline_commit` into story frontmatter, and `/bmad-code-review` uses it as the diff baseline. Because implementation runs in a worktree and sibling stories may merge before review, a raw baseline diff can over-scope the review to other stories' changes. Step 7 now constrains code-review to the story File List. (Bonus: a deterministic baseline + `yolo` keeps code-review fully unattended — no branch-confirm prompt.)
- **`project_context` (#2422)** — added to the agent env block (optional, `**/project-context.md`, load-if-exists; the skills self-resolve it).
- **`.decision-log.md` (6.7)** — confirmed planning-only (`bmad-prd` / `bmad-ux` / `bmad-product-brief` / `bmad-spec`); it never coexists with this skill's deferred-decisions log inside the pipeline.

#### 2026-07-15 in-version revision — token-data tuning + always-on usage log

Driven by three consecutive sprints of harness-reported usage data (22 stories, ~25.6M subagent tokens):

- **Always-on token-usage log** — the coordinator writes `{implementation_artifacts}/sprint-epic-<ID>-token-usage.md` for **every sprint by default** (no flag, no request needed): a row per agent spawn (harness-reported `subagent_tokens`, tool calls, wall-clock) including retries and killed/degraded/stalled spawns, per-story totals, and sprint-end step averages, totals, waste %, and trim/bulk observations compared against prior sprints' logs. Coordinator-only — never injected into agent prompts.
- **Step 1.5 classifier: Sonnet → Haiku** with a slim prompt (no env block). Was a flat ~48k/story (~90% fixed prompt overhead) for a keyword-scan rubric. Tier overrides (`--tier=`, `:suffix`) now **skip the classifier entirely**. Safety guard: a `lite` verdict below high confidence is promoted to `standard`.
- **Step 9 (merge fixes + auto-commit): Opus → Sonnet** — 22/22 stories were pure git mechanics (31–43k avg); the ambiguous-conflict hard pause remains the escape hatch.
- **Step 10 folded into the coordinator** — per-story `sprint-status.yaml` updates are inline YAML edits + grep verify; ONE `/bmad-sprint-status` reconcile agent runs at epic close-out (was 52–71k per story).
- **Step 2 elicitation input cap** — reads story description + ACs + Tasks/Subtasks + the epic-context cache; Dev Notes only per-subsection on demand (the step had grown 66k → 98k avg purely from story-file bloat).
- **Mid-epic context recompile** — the epic-context cache recompiles after every 3rd completed story (validated: create-story cost dropped ~40% immediately after a mid-sprint recompile; within-sprint growth was +68–85% without it).
- **Step 7 review liveness protocol** — reviews were the #1 stall source (4 incidents in 3 sprints). The coordinator now nudges silent reviewers via SendMessage (resume beats a ~130k respawn) and must collect late child-hunter findings before Step 9 commits.
- **Steps 5/8 standardized on Opus** across all surfaces (TL;DR, templates, model table) — copies had drifted to Sonnet; every measured run used Opus.

## Installation

```bash
# Auto-detect BMAD version and install matching script
./install-enhanced-sprint.sh

# Force a specific BMAD version
./install-enhanced-sprint.sh --version=6.0.3

# Install globally (all projects)
./install-enhanced-sprint.sh --global

# List available versions
./install-enhanced-sprint.sh --list

# One-liner remote install
curl -sL https://raw.githubusercontent.com/sidtheone/BMAD-OVERRIDE-CLAUDE-SCRIPTS/main/install-enhanced-sprint.sh | bash
```

## Usage in Claude Code

```
/enhanced-automated-sprint 5              # All stories in Epic 5
/enhanced-automated-sprint 5 5-1 5-2      # Specific stories
/enhanced-automated-sprint 5 --parallel 2  # Parallel execution
```

## Adding a New BMAD Version

When BMAD releases a new version (e.g., `6.0.4`):

1. Create a new folder: `mkdir 6.0.4`
2. Copy and adapt scripts: `cp 6.0.3/*.md 6.0.4/`
3. Make version-specific changes in the new folder
4. Update `compatibility.json` — add the new version entry and set `"latest"`
5. Update root-level files to match the latest version
