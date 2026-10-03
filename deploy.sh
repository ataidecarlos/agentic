#!/usr/bin/env bash
# deploy.sh — Deploy agents, skills, prompts, managed config and AGENTS.md to Opencode
#
# Usage:
#   ./deploy.sh                    # Deploy to user-global (~/.config/opencode/)
#   ./deploy.sh --project .        # Deploy to current project (.opencode/)
#   ./deploy.sh --no-config        # Skip the managed config merge (MCP, skills, plugin)
#   ./deploy.sh --no-prompts       # Skip prompt -> command deployment
#
# The deployment is idempotent: running it twice produces the same result and
# never duplicates the AGENTS.md block or any managed config entry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"
SKILLS_DIR="$SCRIPT_DIR/skills"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
CONFIG_SNIPPET="$SCRIPT_DIR/config/agentic.opencode.json"
AGENTS_MD="$SCRIPT_DIR/AGENTS.md"

# Markers used to replace (rather than append) our AGENTS.md block.
BEGIN_MARKER="<!-- agentic:begin -->"
END_MARKER="<!-- agentic:end -->"

# External checkouts referenced by the managed config. These are plugin/skill
# repositories that are NOT vendored in this repo, so the deployment ensures a
# checkout exists and points the config at it.
UNDERSTAND_ANYWHERE_DIR="${UA_DIR:-$HOME/.understand-anything/repo}"
UNDERSTAND_ANYWHERE_URL="${UA_REPO_URL:-https://github.com/Egonex-AI/Understand-Anything.git}"

# Validate source directories exist
[[ -d "$AGENTS_DIR" ]] || { echo "Error: Agents directory not found: $AGENTS_DIR" >&2; exit 1; }
[[ -d "$SKILLS_DIR" ]] || { echo "Error: Skills directory not found: $SKILLS_DIR" >&2; exit 1; }
[[ -f "$AGENTS_MD"   ]] || { echo "Error: AGENTS.md not found: $AGENTS_MD" >&2; exit 1; }

USE_CONFIG=1
USE_PROMPTS=1
for ARG in "$@"; do
    case "$ARG" in
        --no-config)  USE_CONFIG=0 ;;
        --no-prompts) USE_PROMPTS=0 ;;
    esac
done

if [[ "$USE_CONFIG" == "1" && ! -f "$CONFIG_SNIPPET" ]]; then
    echo "Warning: Config snippet not found, skipping managed config merge: $CONFIG_SNIPPET" >&2
    USE_CONFIG=0
fi
if [[ "$USE_PROMPTS" == "1" && ! -d "$PROMPTS_DIR" ]]; then
    echo "Warning: Prompts directory not found, skipping prompt deployment: $PROMPTS_DIR" >&2
    USE_PROMPTS=0
fi

# Parse arguments
PROJECT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --no-config|--no-prompts)
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

# Determine target directories
if [[ -n "$PROJECT" ]]; then
    PROJECT="$(cd "$PROJECT" && pwd)"
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

# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------
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
    AGENT_COUNT=$((AGENT_COUNT + 1))
done

# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
shopt -s nullglob
SKILL_DIRS=("$SKILLS_DIR"/*/)
shopt -u nullglob

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
    echo "Warning: No skill directories found in $SKILLS_DIR" >&2
fi

SKILL_COUNT=0
EMPTY_SKILL_DIRS=()
for DIR in "${SKILL_DIRS[@]}"; do
    SKILL_NAME="$(basename "$DIR")"
    SKILL_MD="$DIR/SKILL.md"

    if [[ ! -f "$SKILL_MD" ]]; then
        # An empty directory is almost always an unpopulated git submodule or a
        # symlink the platform could not materialise. Say so explicitly instead
        # of emitting a generic "SKILL.md not found" warning.
        if [[ -z "$(find "$DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            EMPTY_SKILL_DIRS+=("$SKILL_NAME")
            echo "Warning: Skipping $SKILL_NAME: directory is empty (unpopulated gitlink? add a matching .gitmodules entry or remove it)" >&2
        else
            echo "Warning: Skipping $SKILL_NAME: SKILL.md not found" >&2
        fi
        continue
    fi

    TARGET_SKILL_DIR="$TARGET_SKILLS_DIR/$SKILL_NAME"
    mkdir -p "$TARGET_SKILL_DIR"

    cp -f "$SKILL_MD" "$TARGET_SKILL_DIR/SKILL.md"
    echo "  Skill: $SKILL_NAME"

    # Copy any additional files (scripts/, references/, etc.)
    while IFS= read -r -d '' FILE; do
        RELATIVE_PATH="${FILE#"$DIR"}"
        TARGET_FILE_PATH="$TARGET_SKILL_DIR/$RELATIVE_PATH"
        mkdir -p "$(dirname "$TARGET_FILE_PATH")"
        cp -f "$FILE" "$TARGET_FILE_PATH"
    done < <(find "$DIR" -type f ! -name "SKILL.md" -print0)

    SKILL_COUNT=$((SKILL_COUNT + 1))
done

# ---------------------------------------------------------------------------
# Prompts -> commands
#
# prompts/<name>.md is the canonical prompt. Opencode exposes reusable prompt
# templates as slash commands, so each prompt becomes commands/<name>.md and is
# invocable as /<name>.
# ---------------------------------------------------------------------------
PROMPT_COUNT=0
if [[ "$USE_PROMPTS" == "1" ]]; then
    TARGET_COMMANDS_DIR="$TARGET_BASE/commands"
    mkdir -p "$TARGET_COMMANDS_DIR"

    shopt -s nullglob
    PROMPT_FILES=("$PROMPTS_DIR"/*.md)
    shopt -u nullglob

    for FILE in "${PROMPT_FILES[@]}"; do
        FILENAME="$(basename "$FILE")"
        cp -f "$FILE" "$TARGET_COMMANDS_DIR/$FILENAME"
        echo "  Prompt -> command: /${FILENAME%.md}"
        PROMPT_COUNT=$((PROMPT_COUNT + 1))
    done

    if [[ "$PROMPT_COUNT" -eq 0 ]]; then
        echo "Warning: No prompt files found in $PROMPTS_DIR" >&2
    fi
fi

# ---------------------------------------------------------------------------
# AGENTS.md (idempotent marked block)
# ---------------------------------------------------------------------------
TARGET_AGENTS_MD="$TARGET_BASE/AGENTS.md"
BLOCK="$(printf '%s\n' "$BEGIN_MARKER"; cat "$AGENTS_MD"; printf '%s' "$END_MARKER")"
BLOCK="${BLOCK%"${BLOCK##*[!$'\n']}"}"

if [[ -f "$TARGET_AGENTS_MD" ]]; then
    cp -f "$TARGET_AGENTS_MD" "$TARGET_AGENTS_MD.bak"

    if grep -qF "$BEGIN_MARKER" "$TARGET_AGENTS_MD" && grep -qF "$END_MARKER" "$TARGET_AGENTS_MD"; then
        # Replace the previous block in place; everything outside the markers
        # (global instructions, other blocks) is preserved untouched.
        # The block content is free text and may itself mention the markers, so
        # pair the FIRST begin with the LAST end.
        #
        # The replacement block is passed via a file, not `awk -v`, because -v
        # interprets backslash escape sequences and would corrupt the content.
        BLOCK_FILE="$(mktemp)"
        printf '%s\n' "$BLOCK" > "$BLOCK_FILE"
        BEGIN_LINE="$(grep -nF "$BEGIN_MARKER" "$TARGET_AGENTS_MD.bak" | head -1 | cut -d: -f1)"
        END_LINE="$(grep -qF "$END_MARKER" "$TARGET_AGENTS_MD.bak" && grep -nF "$END_MARKER" "$TARGET_AGENTS_MD.bak" | tail -1 | cut -d: -f1)"
        END_LINE="${END_LINE:-0}"
        awk -v bl="$BEGIN_LINE" -v el="$END_LINE" -v bf="$BLOCK_FILE" \
            -v bm="$BEGIN_MARKER" -v em="$END_MARKER" '
            function emit_block(   line) {
                while ((getline line < bf) > 0) { sub(/\r$/, "", line); print line }
                close(bf)
            }
            # Normalise CRLF to LF so repeat runs are byte-stable.
            { sub(/\r$/, "") }
            NR == bl {
                p = index($0, bm)
                pre = substr($0, 1, p - 1)
                post = substr($0, p + length(bm))
                if (length(pre) > 0) print pre
                emit_block()
                if (length(post) > 0) print post
                skipping = 1
                next
            }
            NR == el {
                p = index($0, em)
                skipping = 0
                rest = substr($0, 1, p - 1) substr($0, p + length(em))
                if (length(rest) > 0) print rest
                next
            }
            !skipping { print }
        ' "$TARGET_AGENTS_MD.bak" > "$TARGET_AGENTS_MD"
        rm -f "$BLOCK_FILE"
        echo "  AGENTS.md: Replaced agentic block (idempotent)"
    elif grep -qF "<!-- Appended from agentic project -->" "$TARGET_AGENTS_MD"; then
        # Migrate a legacy append (old scripts used a plain HTML comment marker)
        # into the marked block so future runs do not keep appending.
        BLOCK_FILE="$(mktemp)"
        printf '%s\n' "$BLOCK" > "$BLOCK_FILE"
        awk -v bf="$BLOCK_FILE" -v m="<!-- Appended from agentic project -->" '
            function emit_block(   line) {
                while ((getline line < bf) > 0) { sub(/\r$/, "", line); print line }
                close(bf)
            }
            { sub(/\r$/, "") }
            index($0, m) == 1 { emit_block(); exit }
            { print }
        ' "$TARGET_AGENTS_MD.bak" > "$TARGET_AGENTS_MD"
        rm -f "$BLOCK_FILE"
        echo "  AGENTS.md: Migrated legacy appended block to marked block"
        echo "  AGENTS.md: Backed up existing file to AGENTS.md.bak"
    else
        cat "$TARGET_AGENTS_MD.bak" | tr -d '\r' > "$TARGET_AGENTS_MD"
        printf '\n%s\n' "$BLOCK" | tr -d '\r' >> "$TARGET_AGENTS_MD"
        echo "  AGENTS.md: Appended agentic block"
        echo "  AGENTS.md: Backed up existing file to AGENTS.md.bak"
    fi
else
    # Normalise CRLF to LF: the deployed AGENTS.md must be byte-stable no matter
    # which platform ran the deploy.
    printf '%s\n' "$BLOCK" | tr -d '\r' > "$TARGET_AGENTS_MD"
    echo "  AGENTS.md: Created with agentic block"
fi

# ---------------------------------------------------------------------------
# External checkouts
#
# Some skill sources are separate plugin repositories rather than directories in
# this repo. The managed config points at them by path, so make sure a checkout
# actually exists. An existing checkout is never modified; update it yourself so
# a deployment can never move your dependency versions under you.
# ---------------------------------------------------------------------------
if [[ -d "$UNDERSTAND_ANYWHERE_DIR/.git" ]]; then
    echo "  Checkout: understand-anything present at $UNDERSTAND_ANYWHERE_DIR"
elif [[ -d "$UNDERSTAND_ANYWHERE_DIR" ]]; then
    echo "Warning: Checkout: $UNDERSTAND_ANYWHERE_DIR exists but is not a git clone; skipping. Remove it and re-run, or clone $UNDERSTAND_ANYWHERE_URL manually." >&2
elif ! command -v git >/dev/null 2>&1; then
    echo "Warning: Checkout: git not found, cannot clone understand-anything. Clone $UNDERSTAND_ANYWHERE_URL to $UNDERSTAND_ANYWHERE_DIR manually." >&2
else
    echo "  Checkout: cloning understand-anything -> $UNDERSTAND_ANYWHERE_DIR"
    mkdir -p "$(dirname "$UNDERSTAND_ANYWHERE_DIR")"
    git clone --depth 1 "$UNDERSTAND_ANYWHERE_URL" "$UNDERSTAND_ANYWHERE_DIR" \
        || echo "Warning: Checkout: clone of understand-anything failed; its skills will not load until this is resolved." >&2
fi

# ---------------------------------------------------------------------------
# Managed config (MCP servers, skill sources, plugins)
#
# Opencode loads exactly one extra config file (OPENCODE_CONFIG), so these must
# be merged into the target's own opencode.json(c). The merge is scoped: only
# keys present in the snippet are touched, and everything else in the target
# config is preserved.
# ---------------------------------------------------------------------------
SERVER_COUNT=0
if [[ "$USE_CONFIG" == "1" ]]; then
    TARGET_CONFIG=""
    for CANDIDATE in "$TARGET_BASE/opencode.jsonc" "$TARGET_BASE/opencode.json"; do
        if [[ -f "$CANDIDATE" ]]; then TARGET_CONFIG="$CANDIDATE"; break; fi
    done
    if [[ -z "$TARGET_CONFIG" ]]; then
        TARGET_CONFIG="$TARGET_BASE/opencode.jsonc"
        printf '{}' > "$TARGET_CONFIG"
        echo "  Config: Created $TARGET_CONFIG"
    fi

    cp -f "$TARGET_CONFIG" "$TARGET_CONFIG.bak"

    if grep -qE '(^[[:space:]]*//|/\*)' "$TARGET_CONFIG"; then
        echo "Warning: Config: $TARGET_CONFIG contained comments; they were stripped by the JSONC merge. Original saved at $TARGET_CONFIG.bak" >&2
    fi

    # Node is guaranteed present wherever Opencode runs, and it parses JSONC
    # reliably. Object keys are sorted recursively so the output is byte-stable;
    # arrays keep their order because precedence depends on it.
    #
    # NOTE: the plugin key is `plugin` (singular) on V1-line OpenCode builds.
    # Builds following the V2 config guide expect `plugins` and reject the
    # singular form. Probe your build before assuming either spelling.
    MERGE_REPORT="$(node -e '
const fs = require("fs");
const [snippetPath, targetPath] = process.argv.slice(1);
const strip = (t) => t
  .replace(/\\uFEFF/, "")
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/(^|[^:"'"'"'\\])\/\/.*$/gm, "$1")
  .replace(/,(\s*[}\]])/g, "$1");
const sortDeep = (v) => {
  if (Array.isArray(v)) return v.map(sortDeep);
  if (v && typeof v === "object") {
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = sortDeep(v[k]);
    return out;
  }
  return v;
};
const snippet = JSON.parse(fs.readFileSync(snippetPath, "utf8"));
let target = {};
try { target = JSON.parse(strip(fs.readFileSync(targetPath, "utf8"))); } catch (e) {}
if (!target || typeof target !== "object" || Array.isArray(target)) target = {};
const report = [];

// MCP servers, merged by name.
const servers = (snippet.mcp && snippet.mcp.servers) || {};
target.mcp = target.mcp && typeof target.mcp === "object" ? target.mcp : {};
target.mcp.servers = target.mcp.servers && typeof target.mcp.servers === "object" ? target.mcp.servers : {};
for (const [name, def] of Object.entries(servers)) {
  target.mcp.servers[name] = def;
  report.push(["mcp", name]);
}

// Arrays are unioned, preserving order: later entries win for skills and plugins.
for (const key of ["skills", "plugin"]) {
  const incoming = snippet[key];
  if (!Array.isArray(incoming)) continue;
  const before = Array.isArray(target[key]) ? target[key] : [];
  const merged = before.slice();
  for (const entry of incoming) if (!merged.includes(entry)) merged.push(entry);
  target[key] = merged;
  for (const entry of merged) if (!before.includes(entry)) report.push([key, entry]);
}

fs.writeFileSync(targetPath, JSON.stringify(sortDeep(target), null, 2) + "\n");
console.log(JSON.stringify({ servers: Object.keys(servers).length, report }));
' "$CONFIG_SNIPPET" "$TARGET_CONFIG")"

    SERVER_COUNT="$(node -e 'console.log(JSON.parse(process.argv[1]).servers)' "$MERGE_REPORT")"
    while IFS= read -r LINE; do
        KEY="${LINE%%|*}"
        VALUE="${LINE#*|}"
        printf "  %s: %s\n" "$KEY" "$VALUE"
    done < <(node -e '
const r = JSON.parse(process.argv[1]);
for (const [k, v] of r.report) console.log(k + "|" + v);
' "$MERGE_REPORT")

    echo "  Config: Merged into $TARGET_CONFIG"
fi

echo ""
echo "Deployed $AGENT_COUNT agent(s), $SKILL_COUNT skill(s), $PROMPT_COUNT prompt(s), $SERVER_COUNT MCP server(s), and AGENTS.md"
echo "Agents:  $TARGET_AGENTS_DIR"
echo "Skills:  $TARGET_SKILLS_DIR"
if [[ "$USE_PROMPTS" == "1" ]]; then echo "Commands: $TARGET_BASE/commands"; fi
if [[ "$USE_CONFIG" == "1" ]]; then echo "Config:  $TARGET_BASE/opencode.jsonc"; fi
echo "AGENTS.md: $TARGET_AGENTS_MD"

if [[ ${#EMPTY_SKILL_DIRS[@]} -gt 0 ]]; then
    echo ""
    echo "Warning: Unpopulated skill directories skipped: ${EMPTY_SKILL_DIRS[*]}" >&2
    echo "Warning: A skill directory with no SKILL.md is either an unpopulated git submodule or a" >&2
    echo "Warning: multi-skill plugin repository. Run 'git submodule update --init --recursive'," >&2
    echo "Warning: or point the config skills array at the skills/ directory of that repository." >&2
fi