# Quickstart & Validation: Cost Tracking Per Workflow Step

**Feature**: `001-cost-tracking-per-step` | **Date**: 2026-07-13

Runnable validation scenarios that prove the feature works end-to-end. Each scenario maps
to Success Criteria in [spec.md](./spec.md) and contracts in
[contracts/commands.md](./contracts/commands.md). This is a validation guide — full
implementation belongs in `tasks.md` and the implementation phase.

## Prerequisites

- POSIX bash + standard utilities (`awk`, `sed`, `grep`, `date`, `printf`, `mktemp`).
- spec-kit `>= 0.4.0` installed in a project.
- The `cost` extension installed: `extension.yml` provisioned and scripts present at
  `.specify/extensions/cost/scripts/bash/`.
- A `.specify/feature.json` pointing at a feature directory (e.g.,
  `001-cost-tracking-per-step`).

## Zero-config sanity check (SC-002, FR-014)

With **no** `cost-config.yml` present:

```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_specify --in-chars 4800 --out-chars 3200
```

**Expected**: one stdout line resembling
`💰 specify: ~1200 in / ~800 out tokens ≈ $0.0060`
(tokens = chars÷4 → 1200 / 800; cost = (1200+800)/1000 × 0.003 = 0.006), and one new line
appended to `.specify/extensions/cost/cost-ledger.jsonl`.

## Scenario 1 — Per-step summary + append (US1, SC-001)

Run a second step and confirm append-only behavior:

```bash
wc -l .specify/extensions/cost/cost-ledger.jsonl            # note current count
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_plan --in-chars 8000 --out-chars 2000
wc -l .specify/extensions/cost/cost-ledger.jsonl            # count increased by exactly 1
```

**Expected**: exactly one new inline summary line for `plan`; ledger line count +1; the
prior `after_specify` line is byte-for-byte unchanged (FR-003).

## Scenario 2 — Report breakdown + cumulative total (US2, SC-003)

```bash
bash .specify/extensions/cost/scripts/bash/report-cost.sh
```

**Expected**: a table with one row per recorded step (step, input, output, per-step USD)
followed by a cumulative total that equals the sum of the per-step costs (SC-003). Only
the current spec's entries appear.

## Scenario 3 — Multi-spec isolation (SC-004)

Record an entry tagged to a different spec, then report:

```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_specify --in-chars 400 --out-chars 400 --note "other spec" \
  && bash .specify/extensions/cost/scripts/bash/report-cost.sh --spec 999-other
# then report the current spec again:
bash .specify/extensions/cost/scripts/bash/report-cost.sh
```

**Expected**: the current-spec report contains **zero** rows from `999-other`
(SC-004). (In real use, `spec` is derived from `.specify/feature.json`; `--spec` is used
here only to exercise isolation.)

## Scenario 4 — Auto breakdown after implement (FR-007, SC-005)

Simulate the `after_implement` hook wiring (record then report):

```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_implement --in-chars 12000 --out-chars 6000
bash .specify/extensions/cost/scripts/bash/report-cost.sh
```

**Expected**: per the manifest, `after_implement` fires `record` **then** `report`
automatically, so the full cumulative breakdown appears without a manual report command
(SC-005).

## Scenario 5 — Non-blocking failure (FR-015, SC-007)

Force a failure (e.g., omit the estimate for `self-report`):

```bash
LINES_BEFORE=$(wc -l < .specify/extensions/cost/cost-ledger.jsonl)
bash .specify/extensions/cost/scripts/bash/record-cost.sh --step after_tasks
echo "exit code: $?"
LINES_AFTER=$(wc -l < .specify/extensions/cost/cost-ledger.jsonl)
```

**Expected**: exactly one stderr line
`⚠️  speckit-cost: <reason> — entry skipped`; **exit code 0**; `LINES_AFTER == LINES_BEFORE`
(no partial entry written) (SC-007).

## Scenario 6 — Empty-state report (FR-017, SC-008)

Against a spec with no entries:

```bash
bash .specify/extensions/cost/scripts/bash/report-cost.sh --spec 000-empty
```

**Expected**: `No cost data recorded for this spec.` and exit code 0 — never an error or
empty table (SC-008).

## Scenario 7 — Reset requires confirmation (US3, SC-006)

```bash
# Without --yes: refuses, ledger unchanged
bash .specify/extensions/cost/scripts/bash/reset-cost.sh
wc -l .specify/extensions/cost/cost-ledger.jsonl     # unchanged

# With --yes: clears only the current spec's entries
bash .specify/extensions/cost/scripts/bash/reset-cost.sh --yes
bash .specify/extensions/cost/scripts/bash/report-cost.sh   # empty-state message
```

**Expected**: unconfirmed reset leaves 100% of entries intact (SC-006); confirmed reset
clears the current spec's entries, and a follow-up report shows the empty state; other
specs' lines remain.

## Traceability

| Scenario | Success Criteria | Contracts |
|----------|------------------|-----------|
| Zero-config | SC-002 | CR-R1..R6 |
| 1 | SC-001 | CR-R5, CR-R6 |
| 2 | SC-003 | CR-P3, CR-P4 |
| 3 | SC-004 | CR-P2 |
| 4 | SC-005 | CR-M3, CR-P3 |
| 5 | SC-007 | CR-R7 |
| 6 | SC-008 | CR-P6 |
| 7 | SC-006 | CR-X1, CR-X2 |
