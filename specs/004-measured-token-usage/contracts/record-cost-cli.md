# Contract: record-cost.sh CLI (cache-aware recording)

**Feature**: `004-measured-token-usage` | **Consumers**: `commands/speckit.cost.record.md` (agent), wrappers

## Invocation

```bash
record-cost.sh --step <after_*> [--model <id>]
  # token-count mode (self-report measured / manual):
  [--in-tokens N] [--out-tokens N]
  [--cache-read-tokens N] [--cache-write-tokens N]   # NEW, optional
  [--source measured|estimated]                       # NEW, optional
  # char-estimation mode (self-report heuristic):
  [--in-chars N] [--out-chars N]
  [--provider P] [--note "..."]
```

## New flag semantics

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--cache-read-tokens` | int ≥ 0 | 0 | Cache-read subset of `--in-tokens` (which stays the TOTAL, host-reported input — research D4). |
| `--cache-write-tokens` | int ≥ 0 | 0 | Cache-write subset of `--in-tokens`. |
| `--source` | enum | `estimated` | Provenance marker for FR-008. `measured` ⇒ ledger records `"source":"measured"`; `estimated` ⇒ field omitted. |

## Validation (all failures → one stderr warning + `exit 0`, FR-013/SC-006)

1. Cache flags must be non-negative integers.
2. Cache flags are **incompatible with char mode**: providing either cache flag
   together with `--in-chars`/`--out-chars` fails as ambiguous (extends the existing
   mixed-mode guard).
3. `--source` accepts exactly `measured` or `estimated`.
4. Existing validations unchanged (step enum, integer guards, provider resolution).

## Pricing

```text
fresh_in = in_tokens − cache_read − cache_write;  if fresh_in < 0 → fresh_in = 0
           and append "; anomaly: cache counts exceed input total" to note

cost_usd = ( fresh_in    × input_rate_M
           + cache_read  × cache_read_rate_M
           + cache_write × cache_write_rate_M
           + out_tokens  × output_rate_M ) / 1e6
```

Rate resolution per [catalog-format.md](catalog-format.md). With both cache counts 0
the computation is arithmetically identical to v1.3.0 (SC-003).

## Ledger emission

Extends `jsonl_emit` with optional fields (see
[ledger-schema.md](ledger-schema.md)): `cache_read_tokens` / `cache_write_tokens`
emitted only when > 0; `source` emitted only when `measured`. Field order:
`...,"input_tokens":N,"output_tokens":N,"cache_read_tokens":N,"cache_write_tokens":N,"model":...`
with `"source"` after `"provider"`. Legacy invocations produce byte-identical
records to v1.3.0.

## Inline summary (stdout, exactly one line)

```text
# legacy path — UNCHANGED (SC-003):
💰 <step>: ~<in> in / ~<out> out tokens ≈ $<cost>[ (fallback rate — "<model>" not in catalog)]

# when cache_read+cache_write > 0, the input segment gains a parenthetical:
💰 <step>: ~<in> in (<cached> cached) / ~<out> out tokens ≈ $<cost>

# when --source measured, a suffix is appended:
💰 <step>: ~<in> in (<cached> cached) / ~<out> out tokens ≈ $<cost> [measured]
```

`<cached>` = cache_read + cache_write. Fallback-rate suffix composes after
`[measured]` when both apply.

## Reference case (verified session, quickstart Scenario 1)

Input `4228197` / cache-read `4010305` / output `49756` on `claude-sonnet-4-6`
(3|15, derived cache read 0.30):

```text
fresh_in = 217892
cost = (217892×3 + 4010305×0.30 + 49756×15) / 1e6 = 2.6031 USD   # naive: 13.4309
```
