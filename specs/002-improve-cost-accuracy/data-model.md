# Data Model: Accurate Model-Aware Cost Calculation

**Branch**: `002-improve-cost-accuracy` | **Date**: 2026-07-13

---

## 1. Model Catalog Entry

The catalog is a plain-text file at `.specify/extensions/cost/model-catalog.txt`.

### Record Format

```
<model-id>|<input_per_M>|<output_per_M>
```

| Field | Type | Constraints |
|---|---|---|
| `model-id` | string | Exact model ID as reported by the harness (e.g., `claude-sonnet-4-6`). No whitespace. |
| `input_per_M` | float | USD per million input tokens. Non-negative. May have decimal point. |
| `output_per_M` | float | USD per million output tokens. Non-negative. May have decimal point. |

**Validation rules**:
- Lines starting with `#` are comments and are ignored.
- Blank lines are ignored.
- Duplicate model IDs: first match wins (consistent with `grep -m 1`).
- Non-numeric rate fields: entry is skipped and a warning is emitted; no rate is returned for that model.
- Model ID may not contain `|`.

### Lookup Semantics

`catalog_get_rates <model_id>` returns `<input_per_M>|<output_per_M>` or empty string if not found.

Partial-prefix matching: if no exact match, try progressively shorter prefixes (first 3 dash-separated segments, then 2). Example: `claude-sonnet-4-5-20250929` → try `claude-sonnet-4` → match row `claude-sonnet-4-6` is NOT used (segments must match). Prefix fallback is a plan-phase decision: **exact match only** in v1 to avoid false positives.

> **Superseded (v1.3.0, 2026-07-16)**: exact-match-only proved too strict in practice —
> host UIs pass display labels like `GPT-5.3-Codex` that never matched. Lookup now uses
> a tolerant ladder (exact → normalized → dots→dashes → longest dash-boundary prefix).
> See [specs/003-tolerant-model-matching/spec.md](../003-tolerant-model-matching/spec.md)
> and the amended [contracts/catalog-format.md](contracts/catalog-format.md).

---

## 2. Rate Resolution State

Internal computation unit: **USD per million tokens (per-M)**. All config values in per-1K are converted to per-M before arithmetic.

| Source | Read As | Converted To |
|---|---|---|
| `model-catalog.txt` column 2/3 | per-M | per-M (no conversion) |
| `cost-config.yml` → `input_rate_per_1k` | per-1K | × 1000 → per-M |
| `cost-config.yml` → `output_rate_per_1k` | per-1K | × 1000 → per-M |
| `cost-config.yml` → `price_per_1k` | per-1K | × 1000 → per-M (applied to both types) |
| Hardcoded default | per-M literal | 3 (input) / 15 (output) |

### Resolution per Token Type

```
resolve_input_rate(model_id):
  1. if input_rate_per_1k in config: return config_input_rate * 1000
  2. if catalog_get_rates(model_id) succeeds: return catalog_input_rate
  3. if price_per_1k in config: return config_price_per_1k * 1000
  4. return 3  (default)

resolve_output_rate(model_id):
  1. if output_rate_per_1k in config: return config_output_rate * 1000
  2. if catalog_get_rates(model_id) succeeds: return catalog_output_rate
  3. if price_per_1k in config: return config_price_per_1k * 1000
  4. return 15 (default)
```

### Cost Formula (unified)

```
cost_usd = (input_tokens * input_rate_M / 1_000_000)
         + (output_tokens * output_rate_M / 1_000_000)
```

This single formula handles all cases (catalog-only, config-only, mixed partial overrides) once rates are resolved to per-M.

---

## 3. Cost Configuration (`cost-config.yml`)

All keys remain optional. New keys (`input_rate_per_1k`, `output_rate_per_1k`) are additive — existing configs without them continue to work.

| Key | Type | Default | Description |
|---|---|---|---|
| `provider` | string | `self-report` | Token count data source |
| `price_per_1k` | float | 0.003 | Legacy blended rate (per 1K tokens). Used as fallback when no catalog match and no per-type rate set. |
| `input_rate_per_1k` | float | *(absent)* | Override input token rate (per 1K). Takes priority over catalog for input. |
| `output_rate_per_1k` | float | *(absent)* | Override output token rate (per 1K). Takes priority over catalog for output. |
| `model` | string | `unknown` | **Deprecated as primary input.** Still read as label fallback if `--model` flag not passed to script. AI command now passes `--model` from harness context. |

---

## 4. Ledger Entry (unchanged schema — v1)

Schema version does not change. The `model` field was already present; it is now populated with the harness-detected model ID rather than the config label.

```json
{
  "v": 1,
  "ts": "2026-07-13T12:00:00Z",
  "step": "after_specify",
  "spec": "002-improve-cost-accuracy",
  "provider": "self-report",
  "input_tokens": 37500,
  "output_tokens": 7500,
  "model": "claude-sonnet-4-6",
  "cost_usd": 0.225000,
  "note": ""
}
```

**`cost_usd` at record time**: computed using the best available rate at that moment (catalog → config → default). Stored for audit trail. `report-cost.sh` ignores this value and recomputes at display time.

---

## 5. Report Row (new column)

The rendered cost table adds a "Cumulative" column. All monetary values display as `$N.NNNN` (4dp USD).

```
| Step    | Input tokens | Output tokens | Cost (USD) | Cumulative |
|---------|-------------:|--------------:|-----------:|-----------:|
| specify |        37500 |          7500 |    $0.2250 |    $0.2250 |
| clarify |         6750 |          2250 |    $0.0540 |    $0.2790 |
| plan    |        13750 |         14500 |    $0.2600 |    $0.5390 |
```

The grand total line below the table equals the Cumulative value in the last row.

---

## 6. State Transitions

```
Record phase (per step):
  harness injects model-id → AI extracts → --model flag → record-cost.sh
    → resolve_input_rate(model_id)  → catalog|config|default → per-M
    → resolve_output_rate(model_id) → catalog|config|default → per-M
    → cost_usd = formula(in, out, rates)
    → append JSONL to ledger

Report phase (on demand):
  for each entry in ledger (current spec):
    extract model, in_tokens, out_tokens
    → resolve rates (same ladder, current config+catalog)
    → recomputed_cost = formula(in, out, rates)
    → cumulative += recomputed_cost
    → render row
  render grand total = cumulative
```
