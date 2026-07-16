# Contract: Model Catalog Format v2 (cache-aware)

**Feature**: `004-measured-token-usage` | **Consumers**: `catalog.sh`, catalog editors
**Supersedes**: [../../002-improve-cost-accuracy/contracts/catalog-format.md](../../002-improve-cost-accuracy/contracts/catalog-format.md) (format section only — matching rules unchanged)

## Line format

```text
model-id|input_per_M_USD|output_per_M_USD[|cache_read_per_M_USD[|cache_write_per_M_USD]]
```

- Comment lines (`#`) and blank lines: ignored (unchanged).
- Fields 1–3: required, semantics unchanged from v1.3.0.
- Fields 4–5: **optional**, USD per million tokens, standard tier.
- A row may supply field 4 without field 5.

## Parsing rules (`_catalog_rows` / `catalog_get_rates`)

1. Rows with `NF >= 3` are candidates (unchanged); fields 4–5 are captured when
   present, trimmed like fields 1–3.
2. `catalog_get_rates <model>` returns `input|output|cache_read|cache_write` where
   the cache positions are **empty strings** when absent from the row.
3. Validation: each present cache field must match `^[0-9]+(\.[0-9]+)?$`. A malformed
   cache field is treated as absent and emits one stderr warning naming the model —
   the row's input/output fields remain usable (same degradation philosophy as
   v1.3.0 `_catalog_validate_rate`).
4. Matching ladder (exact → normalized → dotless → longest dash-boundary prefix) is
   **unchanged** — it operates on field 1 only.

## Rate resolution with cache terms

Per token type, first hit wins (extends the spec 002 FR-004 resolution ladder;
duplicated in `record-cost.sh` and `report-cost.sh` — update both):

| Term | Ladder |
|---|---|
| input | config `input_rate_per_1k`×1000 → catalog f2 → blended `price_per_1k`×1000 → `3` |
| output | config `output_rate_per_1k`×1000 → catalog f3 → blended `price_per_1k`×1000 → `15` |
| cache read | catalog f4 → `0.10 × resolved input rate` |
| cache write | catalog f5 → `1.25 × resolved input rate` |

`resolved input rate` = the value the input ladder produced (so config overrides and
fallbacks propagate into derived cache rates).

## Backward compatibility (SC-005)

- Every pre-feature 3-field row remains valid and resolves to identical input/output
  rates.
- A v1.3.0 `catalog.sh` reading a v2 file ignores fields 4–5 (awk field access) — no
  forward breakage.

## Shipped catalog changes in this feature

- Add `claude-fable-5|3|15` (dogfooding gap — currently hits the fallback warning).
- No cache columns are added at launch: the 0.10×/1.25× derivation reproduces the
  published rates for every current row (research D3). Columns are the escape hatch
  for future divergence.

## Examples

```text
# 3-field row (existing style — cache rates derived: 0.30 read / 3.75 write)
claude-sonnet-4-6|3|15

# 5-field row (explicit cache rates)
example-model|10|40|1|12.5

# 4-field row (explicit read, derived write = 12.5)
example-model-2|10|40|1
```
