# Research: Measured Token Usage and Cache-Aware Cost Pricing

**Feature**: `004-measured-token-usage` | **Date**: 2026-07-16

All unknowns were resolved by direct inspection of the first supported host's session
store (live DuckDB queries against the `events` table, 2026-07-16) and by review of
provider-published cache billing. No NEEDS CLARIFICATION markers remain.

## D1 — Four-term cache-aware pricing

- **Decision**: Price each entry as four independent terms: fresh input, cache read,
  cache write, output. `cost = fresh_in×in_rate + cr×cr_rate + cw×cw_rate + out×out_rate`
  (all per-M rates).
- **Rationale**: Verified that measured input totals are cache-dominated in agentic
  sessions (real case: 4,228,197 input tokens, 4,010,305 of them cache reads = 94.8%).
  Pricing input at full rate overstates the input side 6.8× ($12.68 vs $1.86). Any
  measured-usage feature without cache separation is worse than the heuristic it
  replaces. User confirmed full-fidelity option (B) over subtract-only (A) or a
  blended 0.10 factor (C).
- **Alternatives considered**: (A) subtract cache reads and note them — simplest but
  silently drops the ~10% cache-read cost; (C) effective-input formula
  `fresh + 0.10×cached` — one number, but bakes a provider-specific factor into the
  agent prompt instead of the catalog where rates belong.

## D2 — Catalog format: 3 → 5 fields, backward compatible

- **Decision**: `model-id|input_per_M|output_per_M[|cache_read_per_M[|cache_write_per_M]]`.
  Fields 4–5 optional. Rows with 3 fields remain fully valid.
- **Rationale**: FR-001/SC-005 require pre-feature catalogs to keep working. The
  existing awk parser (`_catalog_rows`, `NF >= 3`) extends naturally; a malformed
  4th/5th field degrades to "absent" with a stderr warning, mirroring the existing
  `_catalog_validate_rate` behavior.
- **Alternatives considered**: separate `cache-catalog.txt` (second file to ship,
  drift risk); keyed `model-id|key=value` syntax (breaks the existing parser and all
  fixtures for no gain).

## D3 — Default cache rates derived from the input rate

- **Decision**: When catalog fields 4–5 are absent: `cache_read = 0.10 × input_rate`,
  `cache_write = 1.25 × input_rate` — applied to the **resolved** input rate (i.e.,
  after the full FR-004 ladder, including config overrides).
- **Rationale**: Matches the dominant provider's published cache billing (Anthropic:
  5-minute-TTL cache writes 1.25×, reads 0.10×). OpenAI cached input is also ≈0.10×.
  For the entire current catalog the derivation reproduces the correct published
  rates, so **no existing row needs cache columns at launch** — columns exist as the
  escape hatch for future divergence. OpenAI does not bill (or report) cache writes,
  so the 1.25× write default is never exercised on those models (write count is 0).
- **Alternatives considered**: hardcode explicit columns for every model (30 rows of
  redundant data to maintain); require columns and fail without them (breaks SC-005).

## D4 — `--in-tokens` stays *total* input; the script separates

- **Decision**: The recording interface keeps `--in-tokens` = total measured input
  (inclusive of cached tokens, exactly as the host reports it). New flags
  `--cache-read-tokens` / `--cache-write-tokens` carry the cache sub-counts. The
  script computes `fresh_in = max(0, in − cr − cw)` at pricing time. The ledger's
  `input_tokens` field keeps its historical meaning (total input).
- **Rationale**: (a) verified that the host's `usage_input_tokens` **includes** cache
  reads (60,914 in / 60,448 cr → 466 fresh in a sampled call) — agents can pass raw
  sums with zero arithmetic, eliminating an entire class of agent-side mistakes;
  (b) `input_tokens` semantics unchanged → no schema version bump (§IV); (c) the
  cr>in anomaly floor (spec edge case) lives in exactly one place.
- **Alternatives considered**: agent-side separation with `--in-tokens` = fresh only —
  context-dependent flag semantics, double implementation (skill prompt + script),
  and historical `input_tokens` would silently change meaning for measured entries.

## D5 — Ledger schema: stay `"v": 1`, additive optional fields

- **Decision**: New optional fields `cache_read_tokens`, `cache_write_tokens`
  (emitted only when > 0) and `source` (emitted only as `"measured"`; absent =
  estimated). No version bump.
- **Rationale**: Constitution §IV requires a bump when field *semantics change*;
  additive optional fields with documented absent-defaults change nothing for
  existing fields. Emit-only-when-set keeps legacy-path records byte-identical
  (SC-003) and old-report compatibility trivial (absent = 0).
- **Alternatives considered**: bump to v2 (forces report to branch on version for
  zero semantic benefit); always emit the new fields (breaks SC-003 byte-identical
  requirement on hosts without measured usage).

## D6 — Measured usage lives *inside* `self-report` (no new provider)

- **Decision**: The provider enum is untouched. Measured session-store usage is the
  preferred data source within the `self-report` branch, ahead of host usage panels,
  ahead of chars÷4.
- **Rationale**: Constitution §III providers describe *who supplies the numbers*
  (agent, log file, developer) — the agent still supplies them here, just from a
  better source. Adding a provider would force config migration and break the
  zero-config promise; a degradation ladder inside self-report needs none.
- **Alternatives considered**: new `session-store` provider — visible in config,
  but every fallback transition would be a provider switch, and hosts without the
  capability would need config edits to avoid warnings.

## D7 — Acquisition flow (agent level, first host: VS Code Copilot)

- **Decision**: The skill instructs the agent to: (1) trigger a store reindex;
  (2) resolve the current session id from the `VSCODE_TARGET_SESSION_LOG` template
  variable (basename); (3) read the window lower bound from the last ledger entry
  for the current spec; (4) run ONE aggregation query grouped by `usage_model`
  scoped to session + window; (5) select the active-model row (normalized label
  match), note other-model rows; (6) pass sums via flags with `--source measured`.
  Any failure at any point → silently continue to the next rung (usage panel →
  chars÷4).
- **Rationale**: All elements verified live: the `events` table exposes
  `usage_input_tokens`, `usage_output_tokens`, `usage_cache_read_tokens`,
  `usage_cache_write_tokens`, `usage_model` per call; `usage_cost` is unpopulated
  (unusable — confirmed empirically); sessions interleave models (claude-fable-5 +
  gpt-4o-mini in one session), so the GROUP BY + exclusion is mandatory for honest
  attribution (FR-012). **Critical verified limitation**: the in-flight session is
  not visible in the store even after reindex (only closed/reloaded sessions are
  indexed) — measured mode will frequently fall back today; it activates for resumed
  sessions and improves automatically as store indexing improves. This is why the
  fallback is a permanent first-class path, not a transition aid.
- **Alternatives considered**: querying the store from `record-cost.sh` (violates §V
  zero-dependencies — requires a DuckDB client binary); parsing session log files
  directly (undocumented format, brittle, host-private).

## D8 — No new configuration keys

- **Decision**: `cost-config.yml` and `config.sh` are untouched. Cache rates come
  from the catalog or the D3 derivation; measured mode needs no opt-in.
- **Rationale**: Zero-config principle (§III). Per-type config overrides
  (`input_rate_per_1k`/`output_rate_per_1k`) continue to control fresh input/output;
  cache rates derive from the resolved input rate, so overrides propagate coherently.
- **Alternatives considered**: `cache_read_rate_per_1k` config keys (nobody has
  asked; the catalog override already covers custom pricing; can be added in a MINOR
  later without breakage).

## D9 — Corrected reference numbers for the motivating case

- **Decision**: Standardize on the exact verified session figures: 4,228,197 in /
  4,010,305 cache-read / 49,756 out on a $3/$15 model. Input-side: naive $12.68 vs
  cache-aware $1.86 (6.8×). Full recorded entry: naive $13.43 vs correct **$2.6031**.
  spec.md US1/SC-002 are amended to cite both figures precisely (the draft's "$1.85"
  was the input-side number presented as the entry total).
- **Rationale**: Quickstart scenarios must assert exact expected values; mixing
  input-side and total figures would make SC-002 untestable as written.

## D10 — Report rendering for cache and source

- **Decision**: `report-cost.sh` reprices with the same four-term formula
  (absent cache fields = 0 → identical to today for legacy entries, SC-004). The
  breakdown table gains a `Src` column (`m` measured / `e` estimated) and the Tokens
  column shows `in (cached)/out` when a cache count is present. Inline summary from
  `record-cost.sh` appends ` (N cached)` inside the input segment and a ` [measured]`
  suffix when `source=measured`; both additions are absent on the legacy path.
- **Rationale**: FR-006/FR-007/FR-008 with zero churn for estimated-only ledgers.
- **Alternatives considered**: separate cache column in the table (width blowout for
  a value that is zero in most rows today).

## Catalog housekeeping (dogfooding gap)

`claude-fable-5` — the model running this feature's own workflow — is missing from
the catalog and hits the fallback warning. Add it as a Sonnet-class row (`3|15`,
Wibey gateway class assumption) as part of this feature.
