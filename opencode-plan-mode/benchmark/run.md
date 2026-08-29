# Run procedure

Run once per target. Results land in `results/`; aggregate in `findings.md`.

## Per target

1. Feed the target text verbatim to OMP plan mode (paste into an OMP plan-mode session) and to the Opencode plan agent (switch to the overridden `plan` agent in the Opencode TUI and paste). Use the SAME model on both sides; record the exact model ID each side used.
2. Capture both plan outputs verbatim to `benchmark/results/<target>-omp.md` and `benchmark/results/<target>-opencode.md` (create the `results/` directory).
3. Score both against `rubric.md`; write a per-target delta note.
4. Aggregate into `benchmark/findings.md`: which dimensions OMP wins and which the distilled prompt reproduces, plus one-line causes for each gap (prompt rule missing vs. model vs. harness mechanism).

## Environment specifics (this machine)

- OMP session model: `deepseek/deepseek-v4-flash`. The `omp` CLI's opencode.ai gateway is rate-limited (weekly 429), so the OMP side runs in a harness session on the same model ID.
- Opencode side: `opencode run --agent plan --model deepseek/deepseek-v4-flash <target-file>` with the override installed at `~/.config/opencode/agents/plan.md`.
- Target 02 requires a local `fd` checkout: clone `github.com/sharkdp/fd` to a scratch dir and run the Opencode agent with that as cwd (the target names the repo; the agent must read the real callsites).
- Target 04: the agent runs with the project root as cwd so `benchmark/fixtures/concurrency-repro` resolves.
- Target 04: for isolation, copy the fixture to a scratch tree (`scratch/bench/04/benchmark/fixtures/concurrency-repro`) so the path resolves without exposing `rubric.md`/`findings.md` to the agent.

### Non-interactive-run discoveries (2026-08-28 run)

- **`--auto` is required for non-interactive runs.** `opencode run` auto-rejects `ask` permissions and terminates the session on the first rejection (probe-confirmed). The shipped frontmatter gates `bash`/`edit` to `ask` — correct for the TUI, fatal for `opencode run`. Use `--auto` (approximates the user approving prompts) and keep cwds isolated so auto-approved writes can only land in the plan-artifact directory.
- **Plan-artifact write is fixed (2026-08-29)**: `agents/plan.md` frontmatter now sets `edit: { "**/plans/*.md": "allow", "*": "deny" }` (the `edit` key gates `write`/`edit`/`apply_patch`; `**/plans/*.md` is project-root-relative — `plans/*.md` alone misses writes when cwd is a subdir of the project root). A strict session can now write the artifact without `--auto`, and non-plan writes are denied. `bash` remains `ask`, so non-interactive runs still need `--auto` (or accept that any bash usage terminates the run).
- **Provider flake**: deepseek-v4-flash occasionally returns an empty completion or truncates the final response at the output-token limit (`step-finish reason=length`). Rerun the affected target; no prompt change involved.

## Model pinning

The same model ID must run both sides; otherwise tag every delta `model-driven` in `findings.md`. The distilled prompt is the only variable under test.

## Refinement loop

Success criterion: the distilled Opencode plan scores within 1 point of the OMP plan on dimensions 1, 2, and 4 for all four targets. For any dimension lagging by ≥2 points, locate the missing/weak rule in `prompts/omp-plan-mode.md`, tighten it, sync the agent body (`agents/plan.md` = prompt verbatim + unchanged appendix), and re-run the affected targets until the criterion holds. Record refinement deltas in `findings.md`.
