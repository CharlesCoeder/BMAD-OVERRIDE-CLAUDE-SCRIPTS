# BMAD-OVERRIDE-CLAUDE-SCRIPTS

Various scripts to make your life easier with BMAD for Claude Code.

## Version Compatibility

Scripts are organized by exact BMAD version. The installer auto-detects your BMAD version and picks the right one.

| Folder  | BMAD Version | Scripts                                                   |
|---------|-------------|-----------------------------------------------------------|
| `6.0.3` | 6.0.3       | `enhanced-automated-sprint.md`, `claude-hotfix-interaction-style.md` |

Root-level files are kept as a fallback for the latest version.

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
