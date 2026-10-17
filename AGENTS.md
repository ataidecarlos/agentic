# Project Instructions for AI Agents

This file provides context and instructions for all AI agents working on this project.

## Persistent Memory

This project maintains persistent lessons learned from previous sessions. **At the start of each session, read the memory index and relevant memory files to benefit from past experience.**

### Memory Index

Read `~/.opencode/memory/MEMORY.md` to see all available lessons. This path is a logical home-relative location: on Windows, resolve it through the user's home directory rather than treating `/home/...` as literal.

### Memory Location

Individual memory files are stored at:
```
~/.opencode/memory/
```

### How to Use Memory

1. **At session start**: Read `MEMORY.md` to understand what lessons have been learned
2. **When relevant**: Read specific memory files that relate to your current task
3. **Before making decisions**: Check if a lesson applies to avoid repeating past mistakes
4. **When updating memory**: If you learn something new that relates to an existing lesson, update that file rather than creating a duplicate

### Memory Format

Each memory file has this structure:

```yaml
---
name: lesson-name
description: Brief description of the lesson
metadata:
  type: feedback
---

# Lesson Title

## Content
```

### Current Lessons

As of this session, the following lessons have been learned:

1. **Install Infrastructure** — Skills, agents and prompts install by file placement; `INSTALL.md` is the mechanism, and it needs no edit when the count changes
2. **Avoid Hardcoding** — Don't hardcode provider-specific values in portable agents
3. **Clarify Requirements** — Ask clarifying questions before implementing complex features
4. **Test Integration** — Test agent orchestration integration points early and iterate
5. **Document Memory** — Document memory system conventions for skills clearly

### Proactive Hindsight Suggestions

After completing an implementation where iteration or course correction occurred, proactively suggest running a hindsight pass to capture lessons learned. Suggest it only when:

- A concrete plan was followed but required adjustments
- Assumptions turned out wrong and required backtracking
- Unexpected issues required multiple attempts to resolve
- The implementation succeeded but took more iterations than expected

Do not suggest hindsight for straightforward implementations, non-implementation conversations, or every task. Never run hindsight automatically; suggest it and wait for explicit confirmation.

## Project Structure

```
agentic/
├── commands/         # Slash commands (installed as /<name>)
├── agents/           # Opencode agents (frontmatter + prompt body)
├── skills/           # Opencode skills (one dir per skill, plus git submodules)
├── docs/             # AGENTS-PLAN.md — the pre-task checklist this file refers to
├── config/           # Managed config snippet: MCP servers, skill sources, plugins
├── INSTALL.md        # The installer. There is no deployment script.
└── AGENTS.md         # This file
```

## Agent Orchestration

The `design` pipeline is the planning path. `design` (primary, read-only)
interrogates the request, emits a brief, then dispatches `planner` → `reviewer`
→ `verifier`, in that order and each in a fresh context. Only `design` may launch
subagents — the other stages cannot, so it must call every stage itself.
`reviewer` must return APPROVE before `verifier` runs, and the Reviewer →
Verifier pair runs at most 3 times; unresolved concerns are presented rather
than looped on.

Implementation happens afterwards in the built-in `build` agent via `/build`,
which consumes the plan and reports its `## Verification` output verbatim.

The four backstage files in `agents/` are `hidden: true` — `plan`, `planner`,
`reviewer`, `verifier`. `design` is deliberately **not** hidden, because it has
to appear in the agent picker as the entry point. Hidden controls listings only,
not launching: `design` still dispatches the subagents by ID, and `plan.md` is a
no-body override whose only job is to hide the built-in `plan` agent.

## Install Invariants

There is no deployment script. `INSTALL.md` is the installer, and an agent (or a
person) executes it. These rules are what make that safe to repeat, because the
global Opencode config directory is shared state that other tools also write to.

- Every object maps to exactly one destination. `INSTALL.md` §1 is the authority
  on where: agents, commands and skills under `~/.config/opencode/<kind>/`; a
  *project* `AGENTS.md` at `<project>/AGENTS.md`, **not** `.opencode/AGENTS.md`.
- AGENTS.md is wrapped in a marker pair. A repeat install replaces that block in
  place; it never appends. Do not spell the full marker strings out anywhere
  inside this file — the block is located by matching them, and a second
  occurrence inside the content would truncate the match.
- MCP servers are merged by name from `config/agentic.opencode.json` into the
  target's own `opencode.json(c)`. OpenCode loads only one extra config file
  (selected by `OPENCODE_CONFIG`), so a second `*.opencode.json` file in the
  config directory is silently ignored. That snippet is a merge source, never a
  file to copy.
- `skills` and `plugins` entries are ordered unions. Never sort them; later
  entries win.
- When adding a skill, an agent, or a command, add it to the source tree and add
  a row to `INSTALL.md` if the destination differs from the obvious one. Nothing
  enumerates these files any more, so nothing needs editing when the count
  changes — that is the point of dropping the script.
- Removing one is not enough on its own: nothing prunes an existing install, so
  delete the stale file at the destination too. `INSTALL.md` §7 has the check.
- Commands and agents are separate files with separate bodies. A command that
  only needs to *invoke* an agent should delegate with `agent:` rather than copy
  its prompt. A copy drifts: the stale 95-line `plan-mode.md` this repo deleted
  was a copy of the planner prompt that kept describing a review loop the
  planner had since been forbidden to run.
- Never hand-edit a deployed copy. Edit the source tree and re-install.

## Integrating skills from other repositories

A repository is not a skill just because it is useful. Check its shape first:

- **Single-skill repo** (a root `SKILL.md`): add it as a git submodule under
  `skills/`.
- **Multi-skill plugin repo** (skills nested in `skills/` or a plugin package):
  do NOT put it under `skills/`. Either list its skills directory in the config
  snippet's `skills` array, or install it as a plugin when the project ships
  first-class support for this harness.
- **You want one or two skills out of a multi-skill repo:** vendor those
  directories individually under `skills/`, each keeping its own root `SKILL.md`,
  and record source and licence in the README's provenance table. Vendor the
  *directories*, never the repo. This is how `caveman`, `hindsight`,
  `llm-council`, `grill-me` and `grilling` got here.

Before vendoring, check whether the skill is only an **entry point** to another
one. `grill-me` is seven lines that load `grilling`; shipping it alone produces a
skill that points at nothing, which is how it was broken here before. Copy the
pair, and verify the ID the body names actually exists after install.

OpenCode V2 discovers a file named exactly `SKILL.md` at **any depth** under a
skill source, taking the immediate parent directory name as the skill ID. A
multi-skill repository dropped under `skills/` therefore does not fail loudly —
it registers every nested skill it contains, duplicating the IDs supplied by the
plugin or checkout that already provides them. Keep such repos out of `skills/`.

Config key spellings differ by Opencode version. This repo targets V2:
`plugins`, `skills` (one array), `mcp.servers`, `disabled`. The V1-line
spellings `plugin` (singular) and `mcp` as a flat map are deprecated in the V2
schema and are ignored when present. A rejected key is logged as a
`configuration normalization diagnostic`, and `opencode mcp list` does not
surface it — start the server to see it.

## Key Principles

1. **Single Responsibility** — Each step in a plan should perform a single, clearly defined task
2. **Grounded Discovery** — Use reads, globs, and greps to discover facts, never guess
3. **Concrete Edits** — Every step must specify exact targets and behaviors
4. **No Assumptions** — Mark unverified facts as `unverified — confirm first`

## When in Doubt

If you're unsure about something:
1. Check the memory files for relevant lessons
2. Read the README.md for project documentation
3. Ask the user for clarification rather than guessing
