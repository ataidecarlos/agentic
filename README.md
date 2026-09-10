# agentic

Harness-agnostic agents and skills for AI coding assistants. Currently includes a planning agent that produces decision-complete execution plans with the OMP five-section contract (Context / Approach / Critical files & anchors / Verification / Assumptions & contingencies), concrete edits, grounded discovery, and no unsolicited padding.

## What this is

Two deliverables, one relationship:

- `prompts/plan-mode.md` — the canonical portable prompt. Harness-agnostic prose; usable in any harness that supports a planning agent/persona.
- `agents/plan.md` — the Opencode `plan` agent override. Its body is `prompts/plan-mode.md` **verbatim**.

The invariant: **the agent body is the prompt verbatim.** When the prompt changes, re-sync the agent body (see "Keeping prompt and agent in sync").

## How plan mode works

A planning agent produces exactly one deliverable: a written execution plan an engineer who has not seen the conversation can follow top-to-bottom without making a single design decision. Every plan contains exactly five sections, in order — `## Context`, `## Approach`, `## Critical files & anchors`, `## Verification`, `## Assumptions & contingencies` — and nothing else. The prompt enforces the concrete-edit rule (every step names a verb, an exact target, and the new behavior), grounding-by-discovery (reads, globs, greps, and optional parallel research subagents — never guesses stated as settled), and exclusions for unsolicited padding (no extra sections, no mechanical cleanup tail, no references to the planning conversation itself).

The full canonical text is `prompts/plan-mode.md`; it is not duplicated here.

## Layout

| Path | Purpose |
|---|---|
| `prompts/plan-mode.md` | Canonical portable prompt. Harness-agnostic prose; usable in any harness that supports a planning agent/persona. |
| `agents/plan.md` | Opencode `plan` agent override. Body is `prompts/plan-mode.md` verbatim. |

## The override file (`agents/plan.md`)

The load-bearing block is the frontmatter, reproduced verbatim:

```yaml
---
description: "Planning agent: decision-complete execution plans (Context/Approach/Critical files/Verification/Assumptions) with grounded, concrete edits and no padding."
mode: primary
permission:
  read: allow
  glob: allow
  grep: allow
  edit: deny
  bash: deny
  task: deny
  webfetch: allow
  websearch: allow
  lsp: allow
  skill: allow
  todowrite: allow
---
```

The filename `plan` plus `mode: primary` overrides the built-in plan agent by name. The body is the prompt verbatim. The frontmatter enforces the read-only boundary:

> File edits, shell commands, and subagent delegation are denied. The agent performs discovery with its allowed read-only tools and emits the plan in chat. The user reviews the plan, then switches to the Build agent to implement it.

## Permission model — read this first

Fully read-only. File edits, shell commands, and subagent delegation are denied; `todowrite` is allowed only for planning-state tracking.

## Deployment

Two modes. Keep the agent body and the portable prompt in sync — they are the same text.

### Global (all projects)

```sh
mkdir -p ~/.config/opencode/agents
cp agents/plan.md ~/.config/opencode/agents/plan.md
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force ~/.config/opencode/agents | Out-Null
Copy-Item agents/plan.md ~/.config/opencode/agents/plan.md
```

### Per-project

```sh
mkdir -p <project>/.opencode/agents
cp agents/plan.md <project>/.opencode/agents/plan.md
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force <project>/.opencode/agents | Out-Null
Copy-Item agents/plan.md <project>/.opencode/agents/plan.md
```

The filename `plan` overrides the built-in plan agent by name (`mode: primary`). If a Markdown-name override does not replace the built-in in your Opencode version (check with step 2 of "Install & verify" below), fall back to a JSON override in `opencode.jsonc`:

```jsonc
"agent": {
  "plan": {
    "mode": "primary",
    "prompt": { "file": "~/.config/opencode/prompts/plan-mode.md" },
    "permission": {
      "read": "allow", "glob": "allow", "grep": "allow",
      "edit": "deny",
      "bash": "deny", "task": "deny",
      "webfetch": "allow", "websearch": "allow", "lsp": "allow",
      "skill": "allow", "todowrite": "allow"
    }
  }
}
```

## Install & verify

One pass, two steps. Expected output is given for each.

1. **Copy the override.** Global: `mkdir -p ~/.config/opencode/agents && cp agents/plan.md ~/.config/opencode/agents/plan.md`. Per-project: `mkdir -p <project>/.opencode/agents && cp agents/plan.md <project>/.opencode/agents/plan.md`. (PowerShell: `New-Item -ItemType Directory -Force`, `Copy-Item`.)

2. **Verify registration.** Run `opencode agent list`; expect a `plan (primary)` entry. If `plan` is listed but not primary, or a second `plan` coexists, the Markdown-name override did not replace the built-in — use the JSON fallback above.

## Usage

In the Opencode TUI: switch to the `plan` agent, paste the request, review the plan, then switch to the Build agent to implement. The agent is read-only: file edits, shell commands, and subagent delegation are denied.

Non-interactive one-liner:

```sh
opencode run --agent plan --model <model-id> "<request>"
```

`--auto` is unnecessary because the agent has no `ask`-gated permissions.

## Behaviors & troubleshooting

Behaviors verified against Opencode `0.0.0-arm64-sync-202608280755` with `deepseek/deepseek-v4-flash`. If your version differs, `opencode agent list` and `opencode run --help` are authoritative.

- **Provider flake:** `deepseek/deepseek-v4-flash` occasionally returns an empty completion or truncates the final response at the output-token limit. Fix: rerun the request.
- **Don't trust the model's self-reported tool list** ("list every tool available to you"). Models omit tools (e.g. `write`) from their enumeration. Trust `opencode agent list` and the resolved config instead.

## Keeping prompt and agent in sync

When `prompts/plan-mode.md` changes, copy it verbatim into `agents/plan.md` as the body (the frontmatter stays unchanged), then re-run the install step.

