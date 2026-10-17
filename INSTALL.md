# Installing `agentic` into OpenCode v2

This file *is* the installer. There is no deployment script — the mapping below
is the whole mechanism. Point your agent at this file:

> Read `INSTALL.md` and install this.

Three steps need a human decision, not execution: which optional MCP servers to
keep (§4), where to put a token if you keep the GitHub server (§4), and whether
you want the bundled `AGENTS.md` prose at all (§5). Everything else is mechanical.

## 1. Where each object goes

Global paths are relative to `~/.config/opencode/`, which OpenCode uses on every
platform. On Windows that is `C:\Users\<you>\.config\opencode\`.

| This repo | Global | Per project |
|---|---|---|
| `agents/<name>.md` | `~/.config/opencode/agents/<name>.md` | `<project>/.opencode/agents/<name>.md` |
| `prompts/<name>.md` | `~/.config/opencode/commands/<name>.md` | `<project>/.opencode/commands/<name>.md` |
| `skills/<id>/` | `~/.config/opencode/skills/<id>/` | `<project>/.opencode/skills/<id>/` |
| `AGENTS.md` | `~/.config/opencode/AGENTS.md` | `<project>/AGENTS.md` |
| `config/agentic.opencode.json` | merged into `~/.config/opencode/opencode.jsonc` | merged into `<project>/.opencode/opencode.jsonc` |

Three things in that table are easy to get wrong:

- **`AGENTS.md` is the exception.** Every other object lives under `.opencode/`,
  but a *project* instruction file belongs at `<project>/AGENTS.md`. OpenCode
  discovers instruction files from the workspace up toward your home directory,
  stopping at the project root. A file at `<project>/.opencode/AGENTS.md` is only
  loaded if an agent happens to read inside `.opencode/`, which is not what you
  want for repository-wide guidance.
- **A prompt becomes a command.** `prompts/build.md` installs as
  `commands/build.md` and is invoked as `/build`. Only `.md` files are discovered.
  Nested paths become slash-separated names.
- **The directory name is the skill ID.** `skills/caveman/` is the skill
  `caveman`, and that is the exact, case-sensitive ID the model gets. Copy the
  **whole directory**, not just `SKILL.md` — supporting files such as
  `references/` and `scripts/` resolve relative to `SKILL.md`.

Prefer the global install unless you have a reason not to: the pipeline agents
(`design`, `planner`, `reviewer`, `verifier`) are useful in every project.

## 2. Prepare the checkout

```sh
git submodule update --init --recursive   # identical on Windows
```

`skills/stop-slop` is a submodule. **Confirm `skills/stop-slop/SKILL.md` exists
before step 3.** If it does not, the submodule is uninitialised and copying it
would install an empty skill directory, which OpenCode ignores silently.

The bundled config also points at an Understand Anything checkout for nine more
skills. Clone it if you want them:

```sh
git clone https://github.com/Egonex-AI/Understand-Anything.git ~/.understand-anything/repo
```

Otherwise remove that one entry from the `skills` array in step 4. It is the only
entry, so the array ends up empty — `"skills": []` is the correct result, not a
missing key.

## 3. Copy the files

Everything in `agents/`, `prompts/` and `skills/` installs. Copy directory
contents rather than naming files individually, so a later addition is not
silently missed.

POSIX:

```sh
TARGET=~/.config/opencode
mkdir -p "$TARGET"/agents "$TARGET"/commands "$TARGET"/skills
cp agents/*.md  "$TARGET"/agents/
cp prompts/*.md "$TARGET"/commands/
cp -R skills/.  "$TARGET"/skills/
find "$TARGET"/skills -name .git -prune -exec rm -rf {} +
cp AGENTS.md    "$TARGET"/AGENTS.md
```

PowerShell:

```powershell
$Target = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force $Target\agents, $Target\commands, $Target\skills | Out-Null
Copy-Item agents\*.md  $Target\agents\
Copy-Item prompts\*.md $Target\commands\
Get-ChildItem skills -Directory | ForEach-Object { Copy-Item $_.FullName $Target\skills\ -Recurse -Force }
Get-ChildItem $Target\skills -Recurse -Force | Where-Object Name -eq '.git' | Remove-Item -Recurse -Force
Copy-Item AGENTS.md    $Target\AGENTS.md
```

For a per-project install, substitute `<project>/.opencode/` for the first three
and put `AGENTS.md` at `<project>/AGENTS.md`.

## 4. Merge the config

A file copy cannot do this step. `config/agentic.opencode.json` is a **snippet to
merge**, not a file to copy: OpenCode loads exactly one extra config file, selected
by `OPENCODE_CONFIG`, so a second `*.opencode.json` dropped into the config
directory is silently ignored.

Read the target `opencode.jsonc` (or `opencode.json`) and merge the snippet into
it, then write it back:

1. **Back it up if it exists.** It may contain `//` comments, which are lost when
   you rewrite it as JSON. On the create-it path there is nothing to back up.
2. **`mcp.servers`** — merge by name. A server whose name already exists is
   replaced by the snippet's definition.
3. **`skills` and `plugins`** — ordered unions. Append entries that are not
   already present; keep existing entries and their order. **Never sort these
   two.** Later entries win, so order is meaning, not cosmetics.
4. **Everything else stays untouched**, including `"$schema"`.

If the target does not exist, create it containing the snippet. Merging into
`.opencode/opencode.jsonc` is always a correct per-project destination: OpenCode
loads both `<project>/opencode.jsonc` and `<project>/.opencode/opencode.jsonc`,
and every discovered `.opencode` document overrides every discovered direct one.

Three snippet entries are the author's, not yours. Decide now rather than leaving
them to error at startup:

| Entry | What to do |
|---|---|
| `github` | Reads `GITHUB_PERSONAL_ACCESS_TOKEN` from the environment OpenCode is **launched** from — a shell profile or a system/user environment variable. An export in the installing shell is gone the moment that shell exits. Delete the entry instead if you do not want it. |
| `codegraph`, `graphify`, `claude_context` | Tools and accounts the author has. **Delete all three unless you already use them.** `graphify` and `claude_context` are marked `"disabled": true`, so they are inert, but they are still noise in your configuration. |

## 5. Install `AGENTS.md` without duplicating it

The global `AGENTS.md` is shared state — other tools and other machines write to
it. Wrap the block in markers so a re-install *replaces* it instead of appending a
second copy:

```text
<!-- agentic:begin -->
...the contents of this repo's AGENTS.md...
<!-- agentic:end -->
```

- Preserve every byte outside the markers.
- If the markers are already present, replace the block between them, matching
  the **last** end marker (the content is free text and may mention them).
- An older installer appended its copy under `<!-- Appended from agentic project -->`.
  If you find that and no markers, replace from there to the end of the file.

Wrap it the same way for a per-project install: a project may already have its own
`AGENTS.md`, or other tooling may write one, and the markers are what keep the two
from overwriting each other.

Do **not** write these two marker strings inside this repo's own `AGENTS.md`. The
block is located by matching them, and a second occurrence truncates the match.

**Read what you are installing.** This repo's `AGENTS.md` is written for the
author's machines: it describes the `agentic` tree, this repo's install
invariants, and hardware that is not yours. Installing it globally is how the
author works, but for an unrelated project take only the parts that apply to it.

## 6. Verify

For a per-project install run these from the project directory; for a global
install, from anywhere.

```sh
opencode debug config          # config sources, as OpenCode actually loaded them
opencode debug agents          # agent IDs, modes and hidden flags
opencode api get /api/skill    # every registered skill, with its ID
```

The first two need no running server. The skill call reaches the shared service,
which may start one.

**`debug config`** prints one entry per source. Confirm it names the file you
merged into — `~/.config/opencode/opencode.jsonc` for a global install, or
`<project>/.opencode/opencode.jsonc` for a per-project one — and that the entry's
`info.mcp.servers` holds the servers you kept.

**`debug agents`** should report:

| Agent | `mode` | `hidden` |
|---|---|---|
| `design` | `primary` | `false` |
| `planner`, `reviewer`, `verifier` | `subagent` | `true` |
| `plan` | `primary` | `true` |

`design` must be visible: it is the pipeline's entry point and has to appear in
the agent picker. The other four are `hidden: true` on purpose — `hidden` controls
listings only, not launching, so `design` still dispatches its subagents by ID.

**`/api/skill`** should list `caveman`, `hindsight`, `karpathy-guidelines`,
`llm-council`, `stop-slop`, plus the `understand-*` set if you cloned it. If the
list is empty, the `skills` entry was not merged.

Commands cannot be verified from the CLI — check that `/build`, `/plan-mode` and
`/reviewer` appear in the TUI's command list.

If `debug agents` shows `plan` as visible, the install predates the design
pipeline, or a stale `plan.md` is being picked up from an earlier install.

## 7. Updating or re-installing

Repeat steps 3 to 5. Copying overwrites, the config merge adds only what is
missing, and the `AGENTS.md` block is replaced in place rather than appended — so
a re-install converges instead of accumulating. Step 4 creates the config on a
first install; only its merge rule is repeatable.

To remove the installation, delete the copied files and the `agentic:begin` /
`agentic:end` block from `AGENTS.md`. Leave the config merge alone unless you
added nothing of your own to those keys.

## Not installed

| Path | Why not |
|---|---|
| `config/agentic.opencode.json` | A merge source, not a file to copy — see step 4. |
| `INSTALL.md`, `README.md`, `MCP.md`, `docs/` | Repository documentation for whoever is doing the install. |
| `.opencode/` | Per-project **install output**, not an install source. If this repo has its own copy, it was produced by the old deployment script and is stale; regenerate it with a per-project install rather than trusting it. |
| `skills/stop-slop/.git` | Submodule metadata, not part of the skill. Step 3 strips it. |
