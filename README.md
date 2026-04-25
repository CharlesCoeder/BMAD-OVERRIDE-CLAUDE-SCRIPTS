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

Root-level files are kept as a fallback for the latest version.

> **Note:** No `6.3.0/` folder is shipped — 6.3.x users fall through the compatibility chain to `6.2.0`. This fork is personal and the user runs BMAD 6.4 directly.

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
