#!/usr/bin/env bash
# deploy.sh — Deploy all agents and skills to Opencode
#
# Usage:
#   ./deploy.sh              # Deploy to global location (~/.config/opencode/)
#   ./deploy.sh --project .  # Deploy to current project (.opencode/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
SKILLS_DIR="$SCRIPT_DIR/skills"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"

# Validate source directories exist
if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "Error: Agents directory not found: $AGENTS_DIR" >&2
    exit 1
fi

if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "Error: Skills directory not found: $SKILLS_DIR" >&2
    exit 1
fi

if [[ ! -f "$AGENTS_MD" ]]; then
    echo "Error: AGENTS.md not found: $AGENTS_MD" >&2
    exit 1
fi

# Parse arguments
PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Determine target directories
if [[ -n "$PROJECT" ]]; then
    TARGET_BASE="$PROJECT/.opencode"
    echo "Deploying to project: $TARGET_BASE"
else
    TARGET_BASE="$HOME/.config/opencode"
    echo "Deploying to global: $TARGET_BASE"
fi

TARGET_AGENTS_DIR="$TARGET_BASE/agents"
TARGET_SKILLS_DIR="$TARGET_BASE/skills"

# Create target directories
mkdir -p "$TARGET_AGENTS_DIR"
mkdir -p "$TARGET_SKILLS_DIR"

# Copy all agent files
shopt -s nullglob
AGENT_FILES=("$AGENTS_DIR"/*.md)
shopt -u nullglob

if [[ ${#AGENT_FILES[@]} -eq 0 ]]; then
    echo "Warning: No agent files found in $AGENTS_DIR" >&2
fi

AGENT_COUNT=0
for FILE in "${AGENT_FILES[@]}"; do
    FILENAME="$(basename "$FILE")"
    cp -f "$FILE" "$TARGET_AGENTS_DIR/$FILENAME"
    echo "  Agent: $FILENAME"
    ((AGENT_COUNT++))
done

# Copy all skill directories
shopt -s nullglob
SKILL_DIRS=("$SKILLS_DIR"/*/)
shopt -u nullglob

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
    echo "Warning: No skill directories found in $SKILLS_DIR" >&2
fi

SKILL_COUNT=0
for DIR in "${SKILL_DIRS[@]}"; do
    SKILL_NAME="$(basename "$DIR")"
    SKILL_MD="$DIR/SKILL.md"

    # Validate skill has SKILL.md
    if [[ ! -f "$SKILL_MD" ]]; then
        echo "Warning: Skipping $SKILL_NAME: SKILL.md not found" >&2
        continue
    fi

    TARGET_SKILL_DIR="$TARGET_SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$TARGET_SKILL_DIR"

    # Copy SKILL.md
    cp -f "$SKILL_MD" "$TARGET_SKILL_DIR/SKILL.md"
    echo "  Skill: $SKILL_NAME"

    # Copy any additional files (scripts/, references/, etc.)
    find "$DIR" -type f ! -name "SKILL.md" | while read -r FILE; do
        RELATIVE_PATH="${FILE#$DIR/}"
        TARGET_FILE_PATH="$TARGET_SKILL_DIR/$RELATIVE_PATH"
        TARGET_FILE_DIR="$(dirname "$TARGET_FILE_PATH")"
        mkdir -p "$TARGET_FILE_DIR"
        cp -f "$FILE" "$TARGET_FILE_PATH"
    done

    ((SKILL_COUNT++))
done

# Deploy AGENTS.md (append if exists, copy if not)
TARGET_AGENTS_MD="$TARGET_BASE/AGENTS.md"
if [[ -f "$TARGET_AGENTS_MD" ]]; then
    # Backup existing file
    cp -f "$TARGET_AGENTS_MD" "$TARGET_AGENTS_MD.bak"
    echo "  AGENTS.md: Backed up existing file to AGENTS.md.bak"
    
    # Append new content
    echo "" >> "$TARGET_AGENTS_MD"
    echo "" >> "$TARGET_AGENTS_MD"
    echo "<!-- Appended from agentic project -->" >> "$TARGET_AGENTS_MD"
    echo "" >> "$TARGET_AGENTS_MD"
    cat "$AGENTS_MD" >> "$TARGET_AGENTS_MD"
    echo "  AGENTS.md: Appended project content"
else
    # Copy new file
    cp -f "$AGENTS_MD" "$TARGET_AGENTS_MD"
    echo "  AGENTS.md: Copied new file"
fi

echo ""
echo "Deployed $AGENT_COUNT agent(s), $SKILL_COUNT skill(s), and AGENTS.md"
echo "Agents: $TARGET_AGENTS_DIR"
echo "Skills: $TARGET_SKILLS_DIR"
echo "AGENTS.md: $TARGET_AGENTS_MD"
