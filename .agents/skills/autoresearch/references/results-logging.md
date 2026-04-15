# Results logging

Specification for `autoresearch-results.tsv` — the per-iteration record
of every experiment in a run.

---

## File format

Tab-separated values. Headers on row 1. One row per iteration.

```
iteration\tcommit\tmetric\tdelta\tstatus\tdescription
```

### Field definitions

| Field | Type | Description |
|---|---|---|
| `iteration` | integer | 0-indexed. Never resets — if you run multiple sessions, continue from the last number. |
| `commit` | string | 7-char git short SHA for kept commits. `-` for discards and crashes. |
| `metric` | float | Raw metric value from the Verify command. |
| `delta` | float | `metric − previous_best`. Sign convention: positive = improvement (regardless of higher/lower goal). |
| `status` | enum | One of: `baseline`, `keep`, `discard`, `crash` |
| `description` | string | The hypothesis, one sentence. Include the change type and the expected mechanism. |

---

## Example file

```tsv
iteration	commit	metric	delta	status	description
0	-	85.2	0.0	baseline	initial measurement — test coverage 85.2%
1	a1b2c3d	87.1	+1.9	keep	add tests for auth middleware edge cases
2	-	86.5	-0.7	discard	refactor test helpers (broke 2 existing tests)
3	-	0.0	0.0	crash	add integration tests (postgres connection failed — fix in iter 4)
4	b2c3d4e	88.3	+1.2	keep	add tests for error handling in API routes
5	-	88.1	-0.2	discard	add tests for rate limiter (metric within variance, treated as regression)
6	c3d4e5f	89.0	+0.7	keep	add boundary value tests for form validators
7	d4e5f6g	89.8	+0.8	keep	add tests for session expiry edge cases
8	-	89.2	-0.6	discard	mock external API calls (test isolation but metric regressed)
9	e5f6g7h	90.6	+0.8	keep	add tests for concurrent request handling
10	f6g7h8i	91.1	+0.5	keep	add tests for malformed JSON input handling
```

---

## Progress summary format

Print every 10 iterations. Use this exact format:

```
=== Autoresearch progress — iteration <N> ===
Goal:         <original goal statement>
Baseline:     <iteration 0 metric>
Current best: <best metric so far> (<total delta> from baseline)
Keeps:        <count> (<keeps/total * 100>%)
Discards:     <count>
Crashes:      <count>
Top pattern:  <the change type that has produced the most total delta>
Last 5:       <sequence of keep/discard/crash for iterations N-4 through N>
Est. to goal: <if goal metric is known, N iterations at current rate>
===
```

---

## Interpreting the log

### Healthy run signature
- Keep rate 40-60%
- Delta per keep: consistent small positive gains
- No long crash streaks
- Discards are evenly distributed (not clustered)

### Warning signs

| Pattern | Meaning | Action |
|---|---|---|
| Keep rate < 20% | Hypothesis quality is poor | Re-read full scope, re-read lessons, change direction |
| Keep rate > 80% | Metric may be too easy or Verify too lenient | Tighten the goal |
| Long crash streak (5+) | Verify command is fragile or scope is too risky | Fix Verify or narrow scope |
| Delta per keep shrinking toward 0 | Approaching local optimum | Try more radical changes or declare victory |
| Metric oscillating | Non-deterministic Verify or contradictory changes | Run Verify twice and average; tighten scope |

### Declaring success

Stop the loop when one of these is true:
- Metric has reached the stated goal
- Delta per keep has been below 0.1% for 20 consecutive iterations
  (local optimum with current scope)
- All directions have been exhausted (lessons file confirms this)

In all cases, print a final summary and write a lessons entry covering
the full run before stopping.

---

## File hygiene

- Add `autoresearch-results.tsv` to `.gitignore`. It is a working file.
- Do not edit it manually during a run.
- Between runs, you may archive it:
  `mv autoresearch-results.tsv autoresearch-results-<date>.tsv`
  and start fresh, but keep the lessons file — that is the persistent memory.
