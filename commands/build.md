# Build — consume a validated plan

Implement the validated plan from this conversation.

## Before you start

Locate the plan produced by the `design` pipeline — the document with `## Context`, `## Approach`, `## Critical files & anchors`, `## Verification`, and `## Assumptions & contingencies`. It has already been reviewed for soundness and verified against the repository.

**If there is no such plan in context**, stop and say so. Do not infer one from the surrounding conversation, and do not start implementing from a description — the point of this command is to execute a plan that was validated, not to write one.

## How to execute

1. **Follow `## Approach` in order.** The steps are the plan. Do not reorder them, merge them, or substitute your own.
2. **Treat `## Assumptions & contingencies` as binding.** Where an assumption's condition turns out to be true, take the stated fallback — do not invent a third option.
3. **Start from `## Critical files & anchors`.** Those are the files the plan says to open first; they are real, not guessed.
4. **Do not add scope.** Nothing beyond the plan's steps. No opportunistic refactors, no unsolicited cleanup, no documentation the plan did not ask for.

## When the plan proves wrong

If a step cannot be executed as written — a symbol is not where the plan says, a step's premise does not hold, or two steps conflict — **stop and report it**. Name the step, what you expected, and what you found.

Do not silently work around it. A plan that was verified and still does not match reality means either the plan or the repository changed, and that is a finding worth surfacing rather than papering over.

## Finishing

Run the plan's `## Verification` section and **report its actual output** — the real command and the real result, not a summary that it passed.

Then state plainly which steps completed and which did not. If any step is unfinished, say so rather than implying completion.
