# Contract: Ledger Schema (v1 + additive cache/source fields) and Report Interpretation

**Feature**: `004-measured-token-usage` | **Consumers**: `json.sh`, `report-cost.sh`, external ledger readers

## Record shape

Schema version stays `"v": 1` (research D5 — no existing field changes meaning).

```json
{"v":1,"ts":"2026-07-16T20:00:00Z","step":"after_plan","spec":"004-measured-token-usage","provider":"self-report","source":"measured","input_tokens":4228197,"output_tokens":49756,"cache_read_tokens":4010305,"cache_write_tokens":0,"model":"claude-sonnet-4-6","cost_usd":2.603108,"note":"measured: 36 calls via session store; excluded: gpt-4o-mini (1 call)"}
```

*(Note: `cache_write_tokens` would actually be omitted in this example because it is 0 — shown here only to illustrate placement.)*

## Field contract

| Field | Emission rule | Reader rule |
|---|---|---|
| `cache_read_tokens` | Only when > 0 | Absent ⇒ 0 |
| `cache_write_tokens` | Only when > 0 | Absent ⇒ 0 |
| `source` | Only when `measured` | Absent ⇒ estimated |
| `input_tokens` | Always (unchanged) | **Total** input, inclusive of cache subsets |
| all other fields | Unchanged from v1.3.0 | Unchanged |

Consequences:

- Records written by the legacy path are **byte-identical** to v1.3.0 output (SC-003).
- Pre-feature ledgers parse without modification (SC-004); `jsonl_get_field` returns
  empty for absent fields, which readers coerce to 0/estimated.

## `report-cost.sh` interpretation rules

1. **Repricing**: for every entry, recompute with the four-term formula from
   [record-cost-cli.md](record-cost-cli.md), coercing absent cache fields to 0.
   Legacy entries therefore reprice through the identical two-term arithmetic as
   v1.3.0 (SC-004: bit-for-bit totals).
2. **Cache rate resolution**: same ladder as recording
   ([catalog-format.md](catalog-format.md)); the ladder remains duplicated across
   both scripts — any change to the rate-resolution ladder (spec 002 FR-004) must
   touch both.
3. **Table rendering** (research D10):
   - New `Src` column: `m` when `source=measured`, else `e`.
   - Tokens column shows `in (cached)/out` when `cache_read+cache_write > 0` for the
     row, else the current `in/out` form.
   - Cumulative column and grand-total behavior unchanged.
4. **Mixed ledgers** (FR-006): per-step and cumulative totals must be exact across
   any interleaving of legacy and cache-aware entries.

## Append-only guarantees (Constitution §IV — unchanged)

- Hooks never modify or delete existing lines; only `speckit.cost.reset` truncates,
  with confirmation.
- This feature adds no mutation paths; historical entries are never re-written
  (repricing happens at read time only).
