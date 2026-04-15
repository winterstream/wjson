# Ship workflow — `/autoresearch:ship`

Run a pre-flight checklist before shipping — tests, types, lint, bundle size,
security basics, and a final autoresearch pass on anything that fails.

The ship workflow is not just a checklist. It runs an autoresearch loop on
each failing gate until it passes, then re-checks. You don't ship broken.
You ship when everything is green.

---

## Invocation

```
/autoresearch:ship
```

Optional flags:
```
/autoresearch:ship --fast        # skip slow checks (lighthouse, e2e)
/autoresearch:ship --loop N      # max N autoresearch iterations per gate (default: 20)
/autoresearch:ship --dry-run     # report status without fixing anything
```

---

## The ship checklist

The workflow runs these gates in order. Each gate that fails triggers an
autoresearch sub-loop to fix it before moving to the next gate.

### Gate 1 — Tests pass

```bash
npm test         # Node.js
pytest           # Python
go test ./...    # Go
cargo test       # Rust
```

If tests fail → autoresearch loop on `src/**/*.ts` (or equivalent) with
metric: failing test count (lower is better), max 20 iterations.

### Gate 2 — No type errors

```bash
npx tsc --noEmit              # TypeScript
mypy src/                     # Python
```

If errors found → autoresearch loop on `src/**/*.ts` with
metric: error count (lower is better), max 20 iterations.

### Gate 3 — No lint errors

```bash
npx eslint src/               # JavaScript/TypeScript
ruff check src/               # Python
golangci-lint run             # Go
```

If errors found → autoresearch loop with metric: lint error count (lower is better).
Auto-fixable errors are fixed first (`--fix` flag), then the loop handles the rest.

### Gate 4 — Bundle size (if applicable)

Only runs for frontend projects (detected: `next.config.*`, `vite.config.*`,
`webpack.config.*`).

```bash
npm run build 2>&1 | grep "First Load JS"
```

Threshold: warn if > 300KB, block if > 500KB (configurable via `.autoresearch.yml`).

If over threshold → autoresearch loop on `src/**/*.tsx, src/**/*.ts` with
metric: bundle size in KB (lower is better), max 20 iterations.

### Gate 5 — No hardcoded secrets

```bash
git diff HEAD~1 --diff-filter=A | grep -iE "(api_key|secret|password|token)\s*=\s*['\"][^'\"]{8,}"
```

If secrets found → do NOT autoresearch. Flag for human review. Block ship.

### Gate 6 — Dependency audit

```bash
npm audit --audit-level=high   # Node.js
pip-audit                      # Python
```

If critical vulnerabilities found → autoresearch loop to update affected
dependencies, max 10 iterations.

---

## Ship report

After all gates pass, print:

```
=== Ship report ===
Tests:        ✓ PASS  (247 passing)
Types:        ✓ PASS  (0 errors)
Lint:         ✓ PASS  (0 errors)
Bundle:       ✓ PASS  (187KB)
Secrets:      ✓ PASS  (none detected)
Deps:         ✓ PASS  (0 high/critical)

Autoresearch loops run: <N>
Total improvements: <M> iterations kept

Ready to ship. Run: git push && <your deploy command>
===
```

If any gate is still failing after the max iterations:

```
=== Ship report ===
Tests:        ✓ PASS
Types:        ✗ FAIL  (3 errors remaining after 20 iterations)
              → manual fix required: src/auth/session.ts:47

Ship BLOCKED. Fix the above before shipping.
===
```

---

## Gemini-native enhancement

After all gates pass, use Google Search grounding to check:

```
Search: [your framework] [version] known issues [current year]
Search: [your main dependencies] security advisory [current year]
```

If any critical advisories surface that the dependency audit missed,
flag them before shipping. This is a final sanity check that goes beyond
what local tools can detect.

---

## Configuration via `.autoresearch.yml`

Create this file in your project root to customise ship behaviour:

```yaml
ship:
  bundle_warn_kb: 300
  bundle_block_kb: 500
  max_iterations_per_gate: 20
  skip_gates:
    - lighthouse    # skip if no local server available
  extra_gates:
    - name: "E2E tests"
      command: "npx playwright test"
      metric: "failing tests (lower is better)"
      max_iterations: 10
```
