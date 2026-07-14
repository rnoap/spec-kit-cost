# Quickstart Validation Guide: Accurate Model-Aware Cost Calculation

**Branch**: `002-improve-cost-accuracy` | **Date**: 2026-07-13

---

## Prerequisites

- spec-kit-cost extension installed (`.specify/extensions/cost/` present)
- A spec feature active (`.specify/feature.json` points to a feature directory)
- `bash` available (macOS or Linux)

All commands run from the repository root.

---

## Scenario 1 — Catalog lookup (zero config)

**Goal**: Verify that a known model uses catalog prices automatically.

**Setup**: Ensure `cost-config.yml` has no `input_rate_per_1k` / `output_rate_per_1k` keys (factory defaults are fine).

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_specify \
  --in-tokens 1000 \
  --out-tokens 500 \
  --model claude-sonnet-4-6
```

**Expected output** (claude-sonnet-4-6: input $3/M, output $15/M):
```
💰 specify: ~1000 in / ~500 out tokens ≈ $0.0105
```

**Verify**: `(1000 × 3 / 1_000_000) + (500 × 15 / 1_000_000) = 0.003 + 0.0075 = $0.0105` ✓

---

## Scenario 2 — Premium model (Opus)

**Goal**: Verify Opus pricing is materially different from Sonnet.

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_specify \
  --in-tokens 1000 \
  --out-tokens 500 \
  --model claude-opus-4-8
```

**Expected** (claude-opus-4-8: input $5/M, output $25/M):
```
💰 specify: ~1000 in / ~500 out tokens ≈ $0.0175
```

**Verify**: `(1000 × 5 / 1_000_000) + (500 × 25 / 1_000_000) = 0.005 + 0.0125 = $0.0175` ✓

---

## Scenario 3 — Manual rate override takes priority over catalog

**Goal**: Verify `input_rate_per_1k` in config overrides the catalog input rate.

**Setup**: Add to `cost-config.yml`:
```yaml
input_rate_per_1k: 0.010  # $10/M override
```

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_plan \
  --in-tokens 1000 \
  --out-tokens 500 \
  --model claude-sonnet-4-6
```

**Expected** (input from config $10/M, output from catalog $15/M):
```
💰 plan: ~1000 in / ~500 out tokens ≈ $0.0175
```

**Verify**: `(1000 × 10 / 1_000_000) + (500 × 15 / 1_000_000) = 0.010 + 0.0075 = $0.0175` ✓

**Cleanup**: Remove the override from `cost-config.yml`.

---

## Scenario 4 — Unknown model falls back gracefully

**Goal**: Verify a catalog miss produces a warning but does not block.

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_tasks \
  --in-tokens 500 \
  --out-tokens 200 \
  --model claude-unknown-9
```

**Expected** (warning to stderr, cost uses blended fallback `price_per_1k: 0.003` = 3/M for both types):
- Stderr: `⚠️  speckit-cost: model 'claude-unknown-9' not in catalog — using fallback rate`
- Stdout: `💰 tasks: ~500 in / ~200 out tokens ≈ $0.0021`

**Verify**: `(500 × 3 / 1_000_000) + (200 × 3 / 1_000_000) = 0.0015 + 0.0006 = $0.0021` ✓
Note: Both token types use the same blended rate because `price_per_1k` (the fallback) is a single rate applied uniformly. This is the same behavior as before the catalog was introduced.

---

## Scenario 5 — Report shows cumulative column and recomputes from stored model

**Goal**: Verify the report table has a Cumulative column and recomputes rather than reading stored cost_usd.

**Setup**: Run Scenarios 1 and 2 against the same spec (so at least two ledger entries exist).

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/report-cost.sh
```

**Expected output** (format — values depend on actual ledger entries):
```
## Cost Report: <spec-name>

| Step    | Input tokens | Output tokens | Cost (USD) | Cumulative |
|---------|-------------:|--------------:|-----------:|-----------:|
| specify |         1000 |           500 |    $0.0105 |    $0.0105 |
| specify |         1000 |           500 |    $0.0175 |    $0.0280 |

**Total: $0.0280** (2 step(s))
```

**Verify**:
- "Cumulative" column present ✓
- Last row Cumulative value = Total ✓
- Cost (USD) values reflect catalog rates for the stored model, NOT the old stored `cost_usd` ✓

---

## Scenario 6 — Backward compatibility (legacy blended config)

**Goal**: Verify a project using only `price_per_1k` still works.

**Setup**: `cost-config.yml` with only `price_per_1k: 0.003` (no new keys, no catalog entry for the model).

**Run**:
```bash
bash .specify/extensions/cost/scripts/bash/record-cost.sh \
  --step after_specify \
  --in-tokens 1000 \
  --out-tokens 500 \
  --model completely-unknown-model
```

**Expected**: `💰 specify: ~1000 in / ~500 out tokens ≈ $0.0045`

**Verify**: `(1000 + 500) × 0.003 / 1000 = $0.0045` ✓ (blended fallback)

---

## Checking the catalog directly

```bash
cat .specify/extensions/cost/model-catalog.txt
```

To look up a specific model:
```bash
grep '^claude-sonnet-4-6|' .specify/extensions/cost/model-catalog.txt
```

Expected: `claude-sonnet-4-6|3|15`
