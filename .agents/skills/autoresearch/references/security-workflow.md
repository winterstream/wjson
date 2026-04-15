# Security workflow — `/autoresearch:security`

Autonomous security audit using STRIDE threat modelling and OWASP categories.
Finds vulnerabilities, classifies them by severity, and optionally fixes
confirmed critical and high findings via an autoresearch loop.

---

## Invocation

```
/autoresearch:security                    # full audit, report only
/autoresearch:security --fix              # audit + auto-fix confirmed findings
/autoresearch:security --fail-on critical # exit non-zero if critical found (CI gate)
/autoresearch:security --scope src/api/   # audit a specific directory only
```

---

## Phase 1 — Asset discovery

Map the attack surface:

1. Identify all entry points: API routes, form handlers, file uploads,
   auth flows, webhooks, admin panels
2. Identify all data stores: databases, caches, file system writes,
   environment variables, secrets
3. Identify all trust boundaries: public vs authenticated, user vs admin,
   internal vs external services
4. Map data flows: what user input reaches what data store via what path

Output: `security/audit-<timestamp>/attack-surface-map.md`

### Gemini-native step — Live threat intelligence

Use Google Search grounding to seed the audit with current threats:

```
Search: [your stack] common vulnerabilities [current year]
Search: [your main framework] CVE [current year]
Search: OWASP top 10 [current year]
```

Add any newly discovered attack patterns to the audit queue.
This ensures the audit covers threats that postdate your static analysis tools.

---

## Phase 2 — STRIDE threat model

For each asset and trust boundary, model threats across all 6 STRIDE categories:

| Category | Question to ask |
|---|---|
| **S**poofing | Can an attacker impersonate a user, service, or system? |
| **T**ampering | Can input be modified to alter data or behaviour unexpectedly? |
| **R**epudiation | Can actions be performed without a traceable audit trail? |
| **I**nformation disclosure | Can sensitive data be accessed by unauthorised parties? |
| **D**enial of service | Can the service be made unavailable through normal inputs? |
| **E**levation of privilege | Can a lower-privilege user gain higher-privilege access? |

Output: `security/audit-<timestamp>/threat-model.md`

---

## Phase 3 — Autonomous audit loop

```
LOOP (through all attack vectors from threat model):
  1. Select next untested attack vector
  2. Deep-dive into the relevant code (read fully — do not skim)
  3. Attempt to construct a concrete exploit scenario
  4. Validate with code evidence (file:line + exact scenario)
  5. Classify: severity + OWASP category + STRIDE tag
  6. Log to security-audit-results.tsv
  7. Print coverage summary every 5 iterations
  8. Continue until all vectors tested
```

### Severity classification

| Severity | Definition |
|---|---|
| Critical | Exploitable without authentication, leads to full compromise or data breach |
| High | Exploitable with low-privilege access, significant impact |
| Medium | Requires specific conditions, moderate impact |
| Low | Minor information disclosure, no direct exploitation path |
| Info | Best practice violation, no immediate security impact |

### Evidence requirement

Every finding MUST have:
- File path and line number
- Exact vulnerable code snippet (copy from source, do not paraphrase)
- Concrete exploit scenario (how an attacker would trigger this)
- Proof of exploitability (not theoretical — show the actual path)

Findings without concrete evidence are logged as "unconfirmed" and flagged
for manual review, not included in the fix loop.

---

## Phase 4 — Report generation

Output folder: `security/audit-<timestamp>/`

```
security/audit-20260325-1430/
├── overview.md              ← executive summary + finding counts by severity
├── threat-model.md          ← STRIDE analysis per asset
├── attack-surface-map.md    ← entry points, data flows, trust boundaries
├── findings.md              ← all confirmed findings, sorted by severity
├── owasp-coverage.md        ← coverage matrix — which OWASP categories checked
├── recommendations.md       ← fix guidance for each confirmed finding
└── security-audit-results.tsv ← machine-readable log of all iterations
```

Print summary:
```
=== Security audit summary ===
Critical:  <N>
High:      <N>
Medium:    <N>
Low:       <N>
Info:      <N>
Vectors tested: <N> / <total>
OWASP categories covered: <list>

Full report: security/audit-<timestamp>/overview.md
===
```

---

## Phase 5 — Auto-fix loop (with `--fix`)

Only runs when `--fix` flag is passed.
Only fixes **Confirmed Critical and High** findings.
Uses `recommendations.md` as the fix guide for each finding.

```
FOR EACH confirmed Critical/High finding:
  1. Read the finding + recommendation
  2. Make ONE targeted fix
  3. git commit the fix
  4. Re-run the specific exploit scenario to verify it no longer works
  5. Run full test suite to confirm no regressions
  6. If tests break → revert, try alternative fix
  7. Maximum 3 attempts per finding, then skip and flag for manual review
  8. Log fix outcome to fix-log.md
```

---

## CI/CD gate mode (`--fail-on`)

```bash
/autoresearch:security --fail-on critical
```

Exits with code 1 if any findings at or above the specified severity are found.
Suitable for blocking CI pipelines on critical security issues.

```yaml
# .github/workflows/security.yml
- name: Security audit
  run: gemini --prompt "/autoresearch:security --fail-on critical" --yolo
```
