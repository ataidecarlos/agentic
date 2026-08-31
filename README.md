# opencode-plan-mode

Plan mode for Opencode: a distilled, harness-agnostic planning prompt plus an Opencode `plan` agent override that applies it. The agent produces decision-complete execution plans with the OMP five-section contract (Context / Approach / Critical files & anchors / Verification / Assumptions & contingencies), concrete edits, grounded discovery, and no padding.

## What this is

Two deliverables, one relationship:

- `prompts/plan-mode.md` — the canonical portable prompt. Harness-agnostic prose; usable in any harness that supports a planning agent/persona.
- `agents/plan.md` — the Opencode `plan` agent override. Its body is `prompts/plan-mode.md` **verbatim**.

The invariant: **the agent body is the prompt verbatim.** When the prompt changes, re-sync the agent body (see "Keeping prompt and agent in sync").

## How plan mode works

A planning agent produces exactly one deliverable: a written execution plan an engineer who has not seen the conversation can follow top-to-bottom without making a single design decision. Every plan contains exactly five sections, in order — `## Context`, `## Approach`, `## Critical files & anchors`, `## Verification`, `## Assumptions & contingencies` — and nothing else. The prompt enforces the concrete-edit rule (every step names a verb, an exact target, and the new behavior), grounding-by-discovery (reads, globs, greps, and parallel research subagents — never guesses stated as settled), and hard exclusions (no Non-Goals/Alternatives/Risks/Future-Work sections, no mechanical cleanup tail, no references to the planning conversation itself).

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
  edit:
    "**/plans/*.md": allow
    "*": deny
  bash: ask
  task: allow
  webfetch: allow
  websearch: allow
  lsp: allow
  skill: allow
  todowrite: allow
---
```

The filename `plan` plus `mode: primary` overrides the built-in plan agent by name. The body is the prompt verbatim, plus this appendix:

> You are read-only, then emit a concise chat summary of the plan. Never modify any files and `bash` is permission-gated to ask. Approval = the user reviews the plan and switches to the Build agent. For parallel research, spawn the built-in `Explore` (codebase) and `Scout` (external docs/deps) subagents.

## Permission model — read this first

Two mistakes break adoption. Both are prevented by the frontmatter above:

- **`edit` gates `write`, `edit`, AND `apply_patch`.** There is no separate `write` permission key. To allow the plan artifact, you must configure `edit`, not `write`.
- **Patterns are matched project-root-relative, not cwd-relative.** The glob must be `**/plans/*.md`, NOT `plans/*.md` — the latter fails when the agent runs in a subdirectory of the project root (verified this session: `plans/*.md` → write refused, `**/plans/*.md` → written).
- **The plan artifact is the only writable path.** `**/plans/*.md` → `allow` comes first; `*` → `deny` catches everything else. A non-plan write (e.g. `notes.md`) is denied by the environment itself.
- **`bash: ask`.** In the TUI this prompts the user. In non-interactive `opencode run`, an `ask` permission is auto-rejected and **terminates the session** on the first rejection — use `--auto` there (auto-approves everything not explicitly denied), which approximates the user approving prompts.

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
      "edit": { "**/plans/*.md": "allow", "*": "deny" },
      "bash": "ask", "task": "allow",
      "webfetch": "allow", "websearch": "allow", "lsp": "allow",
      "skill": "allow", "todowrite": "allow"
    }
  }
}
```

The permission glob is always forward-slash `**/plans/*.md` on every OS.

## Install & verify

One pass, four steps. Expected output is given for each.

1. **Copy the override.** Global: `mkdir -p ~/.config/opencode/agents && cp agents/plan.md ~/.config/opencode/agents/plan.md`. Per-project: `mkdir -p <project>/.opencode/agents && cp agents/plan.md <project>/.opencode/agents/plan.md`. (PowerShell: `New-Item -ItemType Directory -Force`, `Copy-Item`.)

2. **Verify registration.** Run `opencode agent list`; expect a `plan (primary)` entry. If `plan` is listed but not primary, or a second `plan` coexists, the Markdown-name override did not replace the built-in — use the JSON fallback above.

3. **Verify the plan artifact is writable.** In the Opencode TUI, switch to `plan` (Tab), paste a real planning request, and confirm the agent writes `plans/<slug>-plan.md`. Non-interactive equivalent: `opencode run --agent plan --model <model-id> --auto --dir . "<request>"`.

4. **Verify everything else is denied.** In the same session, ask the agent to also write an unrelated file (e.g. `notes.md`). It must refuse — the resolved config is `edit: { "**/plans/*.md": "allow", "*": "deny" }`. Confirm no such file appears.

## Usage

In the Opencode TUI: switch to the `plan` agent, paste the request, review the plan, then switch to the Build agent to implement. The agent is read-only and `bash` stays permission-gated to ask.

Non-interactive one-liner:

```sh
opencode run --agent plan --model <model-id> --auto "<request>"
```

`--auto` is required for non-interactive runs; without it, the first `ask`-gated tool call is auto-rejected and terminates the session (see troubleshooting).

## Behaviors & troubleshooting

Behaviors verified against Opencode `0.0.0-arm64-sync-202608280755` with `deepseek/deepseek-v4-flash`. If your version differs, `opencode agent list` and `opencode run --help` are authoritative.

- **Non-interactive `opencode run` terminates on an `ask`-permission rejection** ("The user rejected permission to use this specific tool call."). Cause: `ask` auto-rejects when there is no TUI to answer. Fix: run in the TUI, or pass `--auto`.
- **Plan artifact write fails in a strict read-only session** if the frontmatter lacks the `edit` pattern map (the model reports it inline instead). Fix: ensure `edit: { "**/plans/*.md": "allow", "*": "deny" }` is present (it is, in the shipped file).
- **The model sometimes declines to write the artifact** in short or adversarial prompts (claims "no write tool"), delivering the plan inline instead — observed with `deepseek/deepseek-v4-flash`. This is model persona behavior, not a config defect; real planning flows write the artifact, and the inline fallback is safe. Do not "fix" the config in response.
- **Provider flake:** `deepseek/deepseek-v4-flash` occasionally returns an empty completion or truncates the final response at the output-token limit. Fix: rerun the request.
- **Don't trust the model's self-reported tool list** ("list every tool available to you"). Models omit tools (e.g. `write`) from their enumeration. Trust `opencode agent list` and the resolved config instead.

## Keeping prompt and agent in sync

When `prompts/plan-mode.md` changes, copy it verbatim into `agents/plan.md` as the body (the frontmatter stays unchanged), then re-run the install step.

