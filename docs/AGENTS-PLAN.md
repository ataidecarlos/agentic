# Pre-task Plan

When the task involves >2 file edits or edits in >1 top-level directory, walk these items in order. Every `P<n>: <content>` line must appear in your transcript before your first Edit.

## Checklist

1. **P1. Go to target** — task names a file/symbol/stack line? First tool call goes there. Widen only after that read, with a stated one-line question the next file answers.

2. **P2. Premise check** — write `P2: premise <confirmed|disproved> at <file:line> — <evidence>`.

3. **P3. Prior art** — before writing any helper/feature, Grep 2-3 keyword variants and check nearest utils/lib/. Write `P3: found <path>` or `P3: none — searched: <terms>`.

4. **P4. TASK block** — post before first Edit:
   ```
   GOAL: <one sentence, your own words>
   FILES: <exact paths you will change>
   EST: ~<n> changed lines across <n> files
   DONE-WHEN: <observable check command>
   CONSTRAINTS: <verbatim user constraints>
   ```

5. **P5. Baseline** — run the narrowest test/lint covering FILES; record `BASELINE: <pass | N failures>`.

6. **P6. Size gate** — >3 files or >~150 lines? Split into numbered steps, each ending with a named check before the next step.

7. **P7. Ask vs assume** — ask user ONLY when BOTH: (a) two reasonable readings produce different diffs, AND (b) the repo can't disambiguate. Otherwise write `ASSUMPTION: <choice> because <evidence>`.

8. **P8. Mechanism check** — request names both fix and symptom? Confirm fix intercepts symptom before building. If not, report finding + alternative in <=5 lines.

## Stopping conditions

- **Plan contradiction**: discovered fact contradicts plan premise → STOP, write `PLAN CHANGE:`, update steps.
- **Scope creep**: changes pass 2x EST → STOP, report with options (full change / minimal subset / abort). Don't silently absorb.
- **Multiple definitions**: search matched multiple definitions of the same name → run two tool calls to disambiguate before editing any hit.
- **Unsolicited additions**: about to create a helper/class/file/dependency the task didn't name → check if existing code covers it or if <30 local lines suffice; otherwise propose in one line and let user opt in.
