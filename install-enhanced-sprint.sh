#!/usr/bin/env bash
# ============================================================================
# Enhanced Automated Sprint — Version-Aware Self-Installer
# ============================================================================
#
# Installs the /enhanced-automated-sprint skill into any Claude Code project.
# Auto-detects BMAD version from _bmad/_config/manifest.yaml and installs
# the matching version of the script.
#
# Usage:
#   Local:   ./install-enhanced-sprint.sh
#   Remote:  curl -sL https://raw.githubusercontent.com/sidtheone/BMAD-OVERRIDE-CLAUDE-SCRIPTS/main/install-enhanced-sprint.sh | bash
#
#   Options:
#     --global        Install to ~/.claude/commands/ (available in ALL projects)
#     --force         Overwrite existing installation without prompting
#     --uninstall     Remove the skill
#     --version X.Y.Z Force a specific BMAD version instead of auto-detecting
#     --list          List available versions
#
# ============================================================================

set -euo pipefail

SKILL_NAME="enhanced-automated-sprint"
SKILL_FILE="${SKILL_NAME}.md"
REPO_RAW="https://raw.githubusercontent.com/sidtheone/BMAD-OVERRIDE-CLAUDE-SCRIPTS/main"
COMPAT_URL="${REPO_RAW}/compatibility.json"

# --- Parse flags ---
GLOBAL=false
FORCE=false
UNINSTALL=false
LIST=false
FORCE_VERSION=""
for arg in "$@"; do
  case "$arg" in
    --global)    GLOBAL=true ;;
    --force)     FORCE=true ;;
    --uninstall) UNINSTALL=true ;;
    --list)      LIST=true ;;
    --version=*) FORCE_VERSION="${arg#--version=}" ;;
    --version)   echo "Error: --version requires a value (e.g., --version=6.0.3)"; exit 1 ;;
    --help|-h)
      echo "Usage: $0 [--global] [--force] [--uninstall] [--version=X.Y.Z] [--list]"
      echo "  --global        Install to ~/.claude/commands/ (all projects)"
      echo "  --force         Overwrite without prompting"
      echo "  --uninstall     Remove the skill"
      echo "  --version=X.Y.Z Force a specific BMAD version (skip auto-detection)"
      echo "  --list          List available versions"
      exit 0
      ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# --- Find project root ---
find_project_root() {
  local dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.claude" ] || [ -d "$dir/_bmad" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# --- Detect BMAD version from manifest.yaml ---
detect_bmad_version() {
  local project_root="$1"
  local manifest="$project_root/_bmad/_config/manifest.yaml"

  if [ ! -f "$manifest" ]; then
    echo ""
    return
  fi

  # Extract version from manifest (handles "  version: X.Y.Z")
  local version
  version=$(grep -m1 'version:' "$manifest" | sed 's/.*version:[[:space:]]*//' | tr -d '"' | tr -d "'")
  echo "$version"
}

# --- Find best matching version folder ---
# Exact match first, then closest lower version
find_best_version() {
  local target="$1"
  local compat_file="$2"

  if [ -z "$target" ]; then
    # No version detected — use latest
    if command -v python3 &> /dev/null; then
      python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('latest',''))" < "$compat_file"
    else
      grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' "$compat_file" | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"//' | tr -d '"'
    fi
    return
  fi

  # Check for exact match
  if command -v python3 &> /dev/null; then
    local result
    result=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
target = '$target'
versions = list(d.get('versions', {}).keys())

# Exact match
if target in versions:
    print(target)
    sys.exit(0)

# Find closest lower version (semver comparison)
from functools import cmp_to_key
def ver_tuple(v):
    return tuple(int(x) for x in v.split('.'))

target_t = ver_tuple(target)
lower = [v for v in versions if ver_tuple(v) <= target_t]
if lower:
    lower.sort(key=lambda v: ver_tuple(v), reverse=True)
    print(lower[0])
else:
    # No lower version — use latest as fallback
    print(d.get('latest', ''))
" < "$compat_file")
    echo "$result"
  else
    # Fallback: try exact match or latest
    if grep -q "\"$target\"" "$compat_file"; then
      echo "$target"
    else
      grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' "$compat_file" | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"//' | tr -d '"'
    fi
  fi
}

# --- List available versions ---
if [ "$LIST" = true ]; then
  echo "Fetching available versions..."
  COMPAT_TMP=$(mktemp)
  trap 'rm -f "$COMPAT_TMP"' EXIT

  if command -v curl &> /dev/null; then
    curl -sL "$COMPAT_URL" -o "$COMPAT_TMP"
  elif command -v wget &> /dev/null; then
    wget -q "$COMPAT_URL" -O "$COMPAT_TMP"
  else
    echo "Error: Neither curl nor wget found."
    exit 1
  fi

  if command -v python3 &> /dev/null; then
    python3 -c "
import json, sys
d = json.load(open('$COMPAT_TMP'))
latest = d.get('latest', '')
print('Available versions:')
print()
for ver, info in sorted(d.get('versions', {}).items()):
    marker = ' (latest)' if ver == latest else ''
    scripts = ', '.join(info.get('scripts', []))
    changelog = info.get('changelog', 'No changelog')
    print(f'  {ver}{marker}')
    print(f'    Scripts: {scripts}')
    print(f'    Changes: {changelog}')
    print()
"
  else
    echo "Available versions (install python3 for detailed view):"
    grep -o '"[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"' "$COMPAT_TMP" | tr -d '"' | sort -V | while read -r v; do
      echo "  $v"
    done
  fi

  # Also detect local BMAD version if in a project
  if PROJECT_ROOT=$(find_project_root 2>/dev/null); then
    LOCAL_VER=$(detect_bmad_version "$PROJECT_ROOT")
    if [ -n "$LOCAL_VER" ]; then
      echo "Your BMAD version: $LOCAL_VER"
    fi
  fi
  exit 0
fi

# --- Find project root ---
if [ "$GLOBAL" = true ]; then
  PROJECT_ROOT=""
else
  PROJECT_ROOT=$(find_project_root) || {
    echo "Error: Not inside a Claude Code project (no .claude/ or _bmad/ directory found)."
    echo "Run from your project root, or use --global to install for all projects."
    exit 1
  }
fi

# --- Determine BMAD version (before target dir — version affects install path) ---
if [ -n "$FORCE_VERSION" ]; then
  BMAD_VERSION="$FORCE_VERSION"
  echo "Using forced version: $BMAD_VERSION"
elif [ -n "$PROJECT_ROOT" ]; then
  BMAD_VERSION=$(detect_bmad_version "$PROJECT_ROOT")
  if [ -n "$BMAD_VERSION" ]; then
    echo "Detected BMAD version: $BMAD_VERSION"
  else
    echo "Warning: Could not detect BMAD version (no manifest.yaml found)."
    echo "Will use latest available version."
    BMAD_VERSION=""
  fi
else
  echo "Global install — will use latest available version."
  BMAD_VERSION=""
fi

# --- Version comparison helper ---
# Returns 0 (true) if $1 >= $2 in semver
version_gte() {
  local v1="$1" v2="$2"
  if [ "$v1" = "$v2" ]; then return 0; fi
  local IFS=.
  local i v1_parts=($v1) v2_parts=($v2)
  for ((i=0; i<3; i++)); do
    local a="${v1_parts[$i]:-0}" b="${v2_parts[$i]:-0}"
    if [ "$a" -gt "$b" ] 2>/dev/null; then return 0; fi
    if [ "$a" -lt "$b" ] 2>/dev/null; then return 1; fi
  done
  return 0
}

# --- Determine install architecture (skills vs commands) ---
# BMAD 6.2+ uses .claude/skills/ with SKILL.md entry points
# Pre-6.2 uses .claude/commands/ with flat .md files
USE_SKILLS=false
if [ -n "$BMAD_VERSION" ] && version_gte "$BMAD_VERSION" "6.2.0"; then
  USE_SKILLS=true
fi

# --- Determine target directory ---
if [ "$USE_SKILLS" = true ]; then
  if [ "$GLOBAL" = true ]; then
    TARGET_DIR="$HOME/.claude/skills/${SKILL_NAME}"
  else
    TARGET_DIR="$PROJECT_ROOT/.claude/skills/${SKILL_NAME}"
  fi
  TARGET_PATH="$TARGET_DIR/SKILL.md"
  LEGACY_PATH=""
  if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/commands/$SKILL_FILE" ]; then
    LEGACY_PATH="$PROJECT_ROOT/.claude/commands/$SKILL_FILE"
  elif [ "$GLOBAL" = true ] && [ -f "$HOME/.claude/commands/$SKILL_FILE" ]; then
    LEGACY_PATH="$HOME/.claude/commands/$SKILL_FILE"
  fi
else
  if [ "$GLOBAL" = true ]; then
    TARGET_DIR="$HOME/.claude/commands"
  else
    TARGET_DIR="$PROJECT_ROOT/.claude/commands"
  fi
  TARGET_PATH="$TARGET_DIR/$SKILL_FILE"
  LEGACY_PATH=""
fi

# --- Uninstall ---
if [ "$UNINSTALL" = true ]; then
  removed=false
  # Remove from current target
  if [ -f "$TARGET_PATH" ]; then
    rm "$TARGET_PATH"
    echo "Removed: $TARGET_PATH"
    # Clean up empty skill directory if using skills layout
    if [ "$USE_SKILLS" = true ] && [ -d "$TARGET_DIR" ] && [ -z "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
      rmdir "$TARGET_DIR"
    fi
    removed=true
  fi
  # Also check legacy location
  if [ -n "$LEGACY_PATH" ] && [ -f "$LEGACY_PATH" ]; then
    rm "$LEGACY_PATH"
    echo "Removed legacy: $LEGACY_PATH"
    removed=true
  fi
  if [ "$removed" = false ]; then
    echo "Not installed at: $TARGET_PATH"
  fi
  exit 0
fi

# --- Check existing ---
if [ -f "$TARGET_PATH" ] && [ "$FORCE" != true ]; then
  echo "Already installed at: $TARGET_PATH"
  read -rp "Overwrite? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# --- Create directory ---
mkdir -p "$TARGET_DIR"

# --- Determine source ---
# Priority: 1) Local versioned folder, 2) Remote versioned folder, 3) Fallback to root

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLED=false

# Try local versioned folder first
if [ -n "$BMAD_VERSION" ] && [ -f "$SCRIPT_DIR/$BMAD_VERSION/$SKILL_FILE" ]; then
  cp "$SCRIPT_DIR/$BMAD_VERSION/$SKILL_FILE" "$TARGET_PATH"
  echo "Installed from local ($BMAD_VERSION): $SCRIPT_DIR/$BMAD_VERSION/$SKILL_FILE"
  INSTALLED=true
fi

# Try local root fallback
if [ "$INSTALLED" = false ] && [ -f "$SCRIPT_DIR/$SKILL_FILE" ] && [ "$SCRIPT_DIR/$SKILL_FILE" != "$TARGET_PATH" ]; then
  cp "$SCRIPT_DIR/$SKILL_FILE" "$TARGET_PATH"
  echo "Installed from local (root): $SCRIPT_DIR/$SKILL_FILE"
  INSTALLED=true
fi

# Download from GitHub (version-aware)
if [ "$INSTALLED" = false ]; then
  echo "Downloading compatibility manifest..."
  COMPAT_TMP=$(mktemp)
  trap 'rm -f "$COMPAT_TMP"' EXIT

  if command -v curl &> /dev/null; then
    curl -sL "$COMPAT_URL" -o "$COMPAT_TMP"
  elif command -v wget &> /dev/null; then
    wget -q "$COMPAT_URL" -O "$COMPAT_TMP"
  else
    echo "Error: Neither curl nor wget found."
    exit 1
  fi

  # Find best matching version
  MATCH_VERSION=$(find_best_version "$BMAD_VERSION" "$COMPAT_TMP")

  if [ -z "$MATCH_VERSION" ]; then
    echo "Error: No compatible version found for BMAD $BMAD_VERSION."
    echo "Run with --list to see available versions."
    exit 1
  fi

  if [ -n "$BMAD_VERSION" ] && [ "$MATCH_VERSION" != "$BMAD_VERSION" ]; then
    echo "Note: No exact match for $BMAD_VERSION. Using closest: $MATCH_VERSION"
  fi

  VERSIONED_URL="${REPO_RAW}/${MATCH_VERSION}/${SKILL_FILE}"
  echo "Downloading from: $VERSIONED_URL"

  if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -sL -w "%{http_code}" "$VERSIONED_URL" -o "$TARGET_PATH")
  elif command -v wget &> /dev/null; then
    wget -q "$VERSIONED_URL" -O "$TARGET_PATH" && HTTP_CODE="200" || HTTP_CODE="404"
  fi

  # If versioned folder 404s, fall back to root
  if [ "${HTTP_CODE:-000}" != "200" ]; then
    echo "Versioned file not found, falling back to root..."
    FALLBACK_URL="${REPO_RAW}/${SKILL_FILE}"
    if command -v curl &> /dev/null; then
      curl -sL "$FALLBACK_URL" -o "$TARGET_PATH"
    elif command -v wget &> /dev/null; then
      wget -q "$FALLBACK_URL" -O "$TARGET_PATH"
    fi
    echo "Downloaded from: $FALLBACK_URL (fallback)"
  else
    echo "Downloaded version $MATCH_VERSION"
  fi
fi

# --- Verify ---
if [ ! -f "$TARGET_PATH" ]; then
  echo "Error: Installation failed — file not created."
  exit 1
fi

# Quick sanity check — frontmatter present?
if ! head -1 "$TARGET_PATH" | grep -q "^---"; then
  echo "Warning: File may be corrupted (missing frontmatter). Check: $TARGET_PATH"
  exit 1
fi

echo ""
echo "Installed: $TARGET_PATH"
if [ -n "${MATCH_VERSION:-}" ]; then
  echo "Version:   $MATCH_VERSION (for BMAD ${BMAD_VERSION:-latest})"
fi
if [ "$USE_SKILLS" = true ]; then
  echo "Format:    .claude/skills/ (BMAD 6.2+)"
else
  echo "Format:    .claude/commands/ (pre-6.2)"
fi
echo ""
echo "Usage in Claude Code:"
echo "  /enhanced-automated-sprint 5              # All stories in Epic 5"
echo "  /enhanced-automated-sprint 5 5-1 5-2      # Specific stories"
echo "  /enhanced-automated-sprint 5 --parallel 2  # Parallel execution"
echo ""
if [ "$GLOBAL" = true ]; then
  echo "Scope: Global (available in all projects)"
else
  echo "Scope: Project ($PROJECT_ROOT)"
fi

# --- Legacy path warning ---
if [ -n "${LEGACY_PATH:-}" ] && [ -f "$LEGACY_PATH" ]; then
  echo ""
  echo "WARNING: Old installation found at: $LEGACY_PATH"
  echo "  BMAD 6.2+ uses .claude/skills/ instead of .claude/commands/"
  echo "  The old file may shadow the new installation."
  echo "  Remove it with: rm \"$LEGACY_PATH\""
fi
