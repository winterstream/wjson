# Plan workflow — `/autoresearch:plan`

Auto-detect the project stack, propose a complete autoresearch configuration,
do a dry run, and hand the ready-to-run command back to the user.

No manual goal/scope/verify required. Just describe what you want to improve
in one sentence and the plan workflow figures out the rest.

---

## Invocation

```
/autoresearch:plan <goal in plain english>
```

Examples:
```
/autoresearch:plan improve test coverage
/autoresearch:plan make the app faster
/autoresearch:plan reduce the bundle size
/autoresearch:plan fix all TypeScript errors
/autoresearch:plan improve the SEO of my blog posts
/autoresearch:plan shrink the Docker image
```

---

## What the plan workflow does

### Step 1 — Detect project stack

Scan the project root for signal files:

| File found | Stack detected |
|---|---|
| `package.json` + `jest.config.*` | Node.js + Jest |
| `package.json` + `vitest.config.*` | Node.js + Vitest |
| `next.config.*` | Next.js |
| `Dockerfile` | Docker |
| `*.tf` | Terraform |
| `.github/workflows/*.yml` | GitHub Actions CI |
| `content/blog/*.md` OR `posts/*.md` | Markdown content/blog |
| `src/**/*.ts` OR `src/**/*.tsx` | TypeScript project |
| `pyproject.toml` OR `setup.py` | Python project |
| `requirements.txt` + `pytest` | Python + pytest |
| `go.mod` | Go project |
| `Cargo.toml` | Rust project |

Print detected stack. If ambiguous, list the top two candidates and ask
the user to confirm before proceeding.

### Step 2 — Map goal to metric + verify command

Use the goal description and detected stack to propose:

| Goal keyword | Metric | Verify command template |
|---|---|---|
| "test coverage" | coverage % (higher is better) | `npm test -- --coverage \| grep "All files"` |
| "bundle size" / "build size" | size in KB (lower is better) | `npm run build 2>&1 \| grep "First Load JS"` |
| "TypeScript errors" / "type errors" | error count (lower is better) | `npx tsc --noEmit 2>&1 \| grep -c "error TS" \|\| echo "0"` |
| "lighthouse" / "performance score" | score 0-100 (higher is better) | `npx lighthouse http://localhost:3000 --output json --quiet 2>/dev/null \| jq '.categories.performance.score * 100'` |
| "docker image" / "image size" | size in MB (lower is better) | `docker build -t bench . -q && docker images bench --format "{{.Size}}"` |
| "flaky tests" | failure count (lower is better) | `for i in {1..5}; do npm test 2>&1; done \| grep -c "FAIL" \|\| echo "0"` |
| "SEO" / "blog" / "content" | SEO score (higher is better) | `node scripts/seo-score.js <detected content path>` |
| "lines of code" / "complexity" | LOC count (lower is better) | `find src/ -name "*.ts" \| xargs wc -l \| tail -1 \| awk '{print $1}'` |
| "CI pipeline" / "pipeline speed" | seconds (lower is better) | `node scripts/estimate-ci-time.js` |
| "Python tests" / "pytest" | coverage % (higher is better) | `pytest --cov=src --cov-report=term-missing \| grep "TOTAL"` |
| "faster" / "performance" / "latency" | p95 ms (lower is better) | `npm run bench 2>&1 \| grep "p95"` |

### Step 3 — Detect scope

Based on goal + stack, propose the tightest scope that covers the goal:

- Test coverage → `src/**/*.ts, src/**/*.test.ts`
- Bundle size → `src/**/*.tsx, src/**/*.ts`
- Docker → `Dockerfile, .dockerignore`
- SEO → `content/blog/*.md` or detected content directory
- TypeScript errors → `src/**/*.ts`
- CI pipeline → `.github/workflows/*.yml`

### Step 4 — Dry run

Run the proposed Verify command once against the current state.

- If it exits 0 and outputs a number → baseline confirmed, proceed
- If it exits non-zero → diagnose and fix the verify command before proposing
- If it hangs → propose a faster alternative

### Step 5 — Output the ready-to-run command

Print this exact block for the user to copy-paste or confirm:

```
=== Autoresearch plan ===
Stack:    <detected stack>
Goal:     <interpreted goal>
Scope:    <proposed scope>
Metric:   <metric name> (<higher/lower> is better)
Verify:   <verify command>
Baseline: <dry run result>

Ready to run. Confirm or adjust any field, then:

/autoresearch
Goal:   <goal>
Scope:  <scope>
Metric: <metric>
Verify: <verify command>

Or for headless overnight mode:
gemini --prompt "Start autoresearch. Goal: <goal>. Scope: <scope>. Metric: <metric — higher/lower is better>. Verify: <command>. Do not pause." --yolo
===
```

If the user says "looks good" or "run it" — start the autoresearch loop
immediately without requiring them to retype the command.

---

## Gemini-native enhancement

After the dry run, use Google Search grounding to calibrate:

- For SEO goals: search for `[target keyword]` to see what top results look like.
  Note any structural patterns (FAQ sections, word count, heading structure)
  that the current content lacks. Add these as initial hypotheses.

- For performance goals: search for `[framework] performance benchmarks [year]`
  to calibrate whether the baseline is already good or has significant headroom.

- For security goals: search for `[stack] common vulnerabilities [year]`
  to seed the initial hypothesis pool with known attack vectors.

This grounding step happens during plan, not during the loop — so it adds
context once without slowing down iterations.

---

## Edge cases

**Goal is too vague** ("make it better"):
Ask one clarifying question: "Better in what way — speed, quality, size,
coverage, or something else?" Then proceed.

**Multiple valid verify commands exist**:
Propose the fastest one. Note the slower alternative in a comment.

**Verify command requires a running server**:
Note this in the plan output. Add a `# requires: local server on :3000`
comment. Suggest the user start it before running the loop.

**No matching stack detected**:
Ask the user to describe their stack in one sentence, then proceed with
a custom verify command.
