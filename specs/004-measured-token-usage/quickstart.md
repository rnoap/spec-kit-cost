# Quickstart: Validating Measured Token Usage and Cache-Aware Pricing

**Feature**: `004-measured-token-usage` | **Date**: 2026-07-16

Runnable end-to-end scenarios proving the feature works. Contracts:
[record-cost-cli.md](contracts/record-cost-cli.md),
[catalog-format.md](contracts/catalog-format.md),
[ledger-schema.md](contracts/ledger-schema.md),
[measured-usage-acquisition.md](contracts/measured-usage-acquisition.md).

## Prerequisites

- Git Bash (Windows) or any POSIX bash.
- Run from the repository root. For isolation, point the scripts at a temp sandbox
  the way the bats helpers do (`SPECKIT_COST_CATALOG`, temp `.specify/` tree), or
  run inside a scratch clone.
- A `.specify/feature.json` pointing at a spec directory (any name works).

## Scenario 1 — Cache-aware pricing with the verified real-session numbers (US1)

```bash
SPECKIT_COST_CATALOG=model-catalog.txt bash scripts/bash/record-cost.sh \
  --step after_plan --model claude-sonnet-4-6 \
  --in-tokens 4228197 --out-tokens 49756 \
  --cache-read-tokens 4010305 --source measured \
  --note "quickstart scenario 1"
```

**Expected**:

```text
💰 plan: ~4228197 in (4010305 cached) / ~49756 out tokens ≈ $2.6031 [measured]
```

- Cost = (217892×3 + 4010305×0.30 + 49756×15)/1e6 = **$2.6031** — not the naive
  $13.4309 (SC-002).
- Ledger line contains `"cache_read_tokens":4010305`, `"source":"measured"`, and
  **no** `cache_write_tokens` field (zero ⇒ omitted).

## Scenario 2 — Legacy path is byte-identical (US3 / SC-003)

```bash
SPECKIT_COST_CATALOG=model-catalog.txt bash scripts/bash/record-cost.sh \
  --step after_plan --model claude-sonnet-4-6 \
  --in-chars 116000 --out-chars 22000
```

**Expected**: output and appended JSONL record are identical to v1.3.0 for the same
invocation — same summary format (no cache parenthetical, no `[measured]`), no new
JSON fields. Diff the record against a v1.3.0-produced one: only `ts` differs.

## Scenario 3 — Derived cache defaults (FR-002)

Same as Scenario 1 but with `--cache-read-tokens 1000000 --in-tokens 1000000
--out-tokens 0`: fresh input = 0, cost = 1,000,000 × (0.10×3)/1e6 = **$0.3000** —
proves the 0.10× derivation with no catalog cache columns present.

## Scenario 4 — Explicit catalog cache rates override derivation (FR-001)

Create a sandbox catalog containing `cachey|10|40|1|12.5`, point
`SPECKIT_COST_CATALOG` at it, and record `--in-tokens 2000000
--cache-read-tokens 1000000 --cache-write-tokens 500000 --out-tokens 100000`:

```text
fresh = 500000 → cost = (500000×10 + 1000000×1 + 500000×12.5 + 100000×40)/1e6 = $16.2500
```

## Scenario 5 — Anomaly floor (edge case)

`--in-tokens 100 --cache-read-tokens 150 --out-tokens 0` → fresh floors at 0, cost
prices only the 150 cache reads, and the note gains the anomaly suffix. Exit code 0.

## Scenario 6 — Cache flags reject char mode (validation)

`--in-chars 400 --cache-read-tokens 10` → one stderr warning (ambiguous usage),
`entry skipped`, exit 0, ledger untouched.

## Scenario 7 — Mixed-ledger report (US1/SC-004, FR-006)

With a ledger containing one pre-feature entry (no cache fields) and the Scenario 1
entry, run:

```bash
bash scripts/bash/report-cost.sh --spec <spec-name>
```

**Expected**: table shows a `Src` column (`e` / `m`), the measured row's Tokens cell
shows the `(cached)` figure, the legacy row reprices to exactly its v1.3.0 value,
and Cumulative/Grand-total equal the sum of both.

## Scenario 8 — Measured acquisition end-to-end (host-dependent, manual)

On VS Code Copilot, after at least one *closed* session with workflow activity:
follow [measured-usage-acquisition.md](contracts/measured-usage-acquisition.md) —
reindex, resolve the session id, run the aggregation SQL, and verify the flags the
skill would pass equal the store's own sums for the window. On any other host,
verify the skill runs rung 2/3 with output indistinguishable from v1.3.0.

## Scenario 9 — Regression suite

```bash
bats tests/bats/
```

**Expected**: all pre-existing tests pass unmodified (SC-003). Known pre-existing
Windows-only failures (4× emoji-grep SC-001, 1× chmod SC-007) are not regressions.
