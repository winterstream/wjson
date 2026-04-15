# Autonomous loop protocol

Detailed specification for each of the 8 phases. The SKILL.md contains the
summary version. Read this reference when you need precise guidance on edge
cases in any phase.

---

## Phase 1 — Review

**Purpose**: Build a complete, accurate picture of current state before
forming any hypothesis. Hypotheses formed without full context waste iterations.

**What to read**:
- Every file in Scope (not just the ones you last touched)
- `git log --oneline -20` — what has been attempted, in order
- `autoresearch-results.tsv` — the full record of what worked and failed
- `autoresearch-lessons.md` — accumulated patterns from prior runs

**What to extract**:
- Current metric trajectory (improving? plateauing? volatile?)
- Which change types produced the most gain per iteration
- Which change types consistently failed
- Which directions have not yet been explored
- Any patterns in crash causes

**Duration**: This phase should take as long as needed to form a genuinely
informed hypothesis. Rushing Phase 1 leads to repeated failures.

---

## Phase 2 — Ideate

**Purpose**: Select ONE hypothesis that has the highest expected gain given
what is known.

**Hypothesis selection criteria** (in order of priority):
1. Builds directly on a proven pattern from the lessons file
2. Explores a direction adjacent to a near-miss (something that almost worked)
3. Combines two near-miss approaches that individually failed
4. Tries the opposite of what consistently failed
5. Applies an externally validated technique (from Search grounding)
6. Tries something entirely untested

**What makes a good hypothesis**:
- Specific: "lazy-load the user avatar component" not "improve performance"
- Testable: produces a measurable delta in the Verify command
- Atomic: one thing changes, one thing is measured
- Explainable in one sentence before you make the change

**What makes a bad hypothesis**:
- Vague: "refactor for clarity"
- Multi-part: "update the API, add caching, and fix the tests"
- Untestable by the Verify command
- Identical to something tried in the last 3 iterations

---

## Phase 3 — Modify

**Purpose**: Implement the hypothesis as a single, clean, minimal change.

**Rules**:
- Touch only files in Scope
- Make the smallest change that tests the hypothesis
- If the change is getting large, stop and split it — make the first half now,
  the second half in the next iteration
- Do not fix unrelated things you notice while editing
- Do not reformat code that is not part of the hypothesis
- Leave comments only if they directly explain the change

**Signs you are over-scoping**:
- You have edited more than 3 files
- The diff is more than ~50 lines
- You are explaining the change with "and also"

When in doubt, make a smaller change. Smaller changes fail faster and teach more.

---

## Phase 4 — Commit

**Purpose**: Create a clean rollback point before any verification risk.

**Command**:
```bash
git add -A && git commit -m "autoresearch iter N: <one-sentence description>"
```

**Commit message format**:
- Always prefix with `autoresearch iter N:`
- One sentence, present tense, describes the change not the goal
- Good: `autoresearch iter 14: lazy-load user avatar to reduce initial bundle`
- Bad: `autoresearch iter 14: improve performance`

**Why commit before verifying**: if the Verify command crashes, hangs, or
corrupts state, you can always `git revert HEAD --no-edit` and return to
a known-good state. If you verify before committing, a crash during
verification leaves you with uncommitted changes and an unknown baseline.

**Never skip this step**, even if the change feels obviously correct.

---

## Phase 5 — Verify

**Purpose**: Get a single numeric measurement of whether the hypothesis helped.

**Execution**:
1. Run the Verify command exactly as specified by the user
2. Extract the numeric metric value
3. Optionally supplement with Google Search grounding (see
   `references/google-search-patterns.md`)
4. Record the raw output for the log

**Handling slow Verify commands**:
If the Verify command takes more than 30 seconds, note this. After the run,
recommend the user find a faster proxy metric — slower verification means
fewer experiments per hour, which compounds negatively over a full night.

**Handling non-deterministic Verify commands**:
If the metric varies significantly between runs on identical code (>5%
variance), note this in the log. Run the Verify command twice and average.
Log both values. Recommend the user address flakiness before the next
overnight run.

---

## Phase 6 — Decide

**Purpose**: Make a clear, mechanical keep/revert decision. No deliberation.

**Decision table**:

| Condition | Action | Log status |
|---|---|---|
| Metric improved (beyond noise threshold) | Keep commit as-is | `keep` |
| Metric unchanged or regressed | `git revert HEAD --no-edit` | `discard` |
| Verify crashed with exit code ≠ 0 | Attempt fix (max 3 tries) then revert | `crash` |
| Verify hung for >60s | Kill process, revert | `crash` |

**Noise threshold**: for metrics with variance, an improvement smaller than
the variance is not a real improvement. If your metric normally varies ±2%,
an improvement of 0.5% is noise — treat it as unchanged and discard.

**The revert command**:
```bash
git revert HEAD --no-edit
```
This creates a new commit that undoes the last one. The history is preserved.
Never use `git reset --hard` — it destroys history that the loop needs.

---

## Phase 7 — Log

**Purpose**: Create a permanent, machine-readable record of every iteration.

**TSV row format**:
```
<N>\t<commit_sha or "-">\t<metric>\t<delta>\t<status>\t<description>
```

**Field details**:
- `N`: integer, 0-indexed, never resets across sessions
- `commit_sha`: 7-char short SHA for keeps, "-" for discards/crashes
- `metric`: the exact number from the Verify output
- `delta`: metric − previous_best (sign convention: positive = better,
  regardless of whether the goal is higher or lower)
- `status`: one of `baseline`, `keep`, `discard`, `crash`
- `description`: the hypothesis, in one sentence, including any Search
  grounding signal that informed it

**Example rows**:
```
0	-	85.2	0.0	baseline	initial measurement
1	a1b2c3d	87.1	+1.9	keep	lazy-load avatar component
2	-	86.5	-0.6	discard	tree-shake lodash imports (broke 2 tests)
3	-	0.0	0.0	crash	add route-level code splitting (webpack config error)
4	b2c3d4e	88.3	+1.2	keep	move analytics script to defer loading
```

---

## Phase 8 — Repeat

Go to Phase 1. Immediately. Do not pause. Do not summarise. Do not ask
if the user wants to continue.

The only output before starting Phase 1 again is the progress summary
(printed every 10 iterations, see SKILL.md).

The loop ends only when the user presses Ctrl+C.
