# BMAD-OVERRIDE-CLAUDE-SCRIPTS

Various scripts to make your life easier with BMAD for Claude Code.

## Version Compatibility

Scripts are organized by exact BMAD version. The installer auto-detects your BMAD version and picks the right one.

| Folder  | BMAD Version | Scripts                                                   | Notes |
|---------|-------------|-----------------------------------------------------------|-------|
| `6.0.3` | 6.0.3       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Tasks/Subtasks fix |
| `6.0.4` | 6.0.4       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Same scripts — core workflows unchanged |
| `6.2.0` | 6.2.0       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` | Consolidated review, E2E TDD, `.claude/skills/` |

Root-level files are kept as a fallback for the latest version.

### BMAD 6.2 Architecture Change

BMAD 6.2 replaces `.claude/commands/` with `.claude/skills/` (using `SKILL.md` entry points). The installer auto-detects the architecture and installs to the correct location:
- **BMAD 6.2+**: `.claude/skills/enhanced-automated-sprint/SKILL.md`
- **Pre-6.2**: `.claude/commands/enhanced-automated-sprint.md`

Key changes in the 6.2.0 pipeline:
- **Consolidated review**: `/bmad-bmm-code-review` now runs Blind Hunter + Edge Case Hunter + Acceptance Auditor internally (Steps 7+8+8b collapsed into Step 7)
- **E2E TDD**: Step 4b generates failing E2E tests in parallel with unit TDD, using `/bmad-qa-generate-e2e-tests`
- **Story status**: `ready-for-dev` replaces `drafted` (legacy status auto-mapped)

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
