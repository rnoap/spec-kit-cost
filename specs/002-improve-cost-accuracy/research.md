# Research: Accurate Model-Aware Cost Calculation

**Branch**: `002-improve-cost-accuracy` | **Date**: 2026-07-13

---

## Decision 1: Catalog file format

**Decision**: Pipe-delimited plain text (`model-id|input_per_M|output_per_M`), one model per line. Comment lines begin with `#`.

**Rationale**: Parseable with only `grep` + `cut` — no external parser required, satisfying Constitution §V. Pipe delimiter avoids collision with model ID hyphens. Easy to diff and review.

**Example**:
```
claude-sonnet-4-6|3|15
gpt-5.4-mini|0.75|4.5
```

**Alternatives considered**:
- CSV: commas appear in model display names and could appear in future model IDs.
- YAML/JSON: requires an external parser (yq, python, jq) — violates §V.
- Key=Value: would require two lines per model, making ordering and partial-match lookup harder.

---

## Decision 2: Internal rate unit — per-million tokens

**Decision**: All internal cost computations use **USD per million tokens (per-M)**. The catalog stores per-M directly. Config keys (`input_rate_per_1k`, `output_rate_per_1k`, `price_per_1k`) are **normalized to per-M at resolution time** (multiply by 1000) before any arithmetic.

**Rationale**: The wibey-cli authoritative source uses per-M. Mixing per-M (catalog) and per-1K (config) in a single `awk` expression without explicit normalization is a silent numeric footgun — especially on partial-override paths where one rate comes from the catalog and the other from config. Normalizing at resolution keeps the cost formula a single expression: `(in * in_rate_M / 1_000_000) + (out * out_rate_M / 1_000_000)`.

**Unit conversion**:
- `price_per_1k` = 0.003 → `price_per_M` = 3.0
- `input_rate_per_1k` = 0.005 → `input_rate_per_M` = 5.0

**Alternatives considered**: Storing catalog in per-1K — would introduce floating-point representation issues for small values (e.g., Haiku output $0.005/1K vs $5/M); per-M is the canonical Anthropic/OpenAI unit.

---

## Decision 3: Model identity detection mechanism

**Decision**: The AI agent executing `speckit.cost.record.md` reads the **harness-injected "Current model: <model-id>"** string from its session context (visible in the system reminder). This is an authoritative signal from the Wibey harness, not the model's own self-identification. The agent extracts the canonical model ID (e.g., `claude-sonnet-4-6`) and passes it via `--model <id>` to `record-cost.sh`.

**Rationale**: Environment variable scan (`env | grep -iE 'wibey|model|anthropic|claude'`) confirmed no `WIBEY_MODEL` or equivalent env var is injected by the current harness. The only programmatic signal is the session context string. Since the harness injects it (not the model self-reporting), it is authoritative and consistent across model versions.

**Auto-tier behavior**: When `auto-elite` is active, the harness injects the executor model ID (`claude-sonnet-4-6`), not `auto-elite`. Advisor-model spend (Opus) is billed separately by the harness and is not visible in this hook's token counts. Therefore, auto-tier steps are costed at the executor model's rate, which matches the tokens available to this hook.

**Alternatives considered**:
- AI self-identification: unreliable — models can misidentify their version.
- `ANTHROPIC_BASE_URL` parsing: encodes the gateway URL, not the model.
- Asking the user to set `model` in `cost-config.yml`: rejected (user's stated requirement is zero-config accuracy).

---

## Decision 4: Rate resolution priority (FR-004)

**Decision**: For each token type (input / output), resolve rate independently in this order:
1. Manual config override: `input_rate_per_1k` (converted × 1000 to per-M)
2. Catalog lookup for detected model: `input_rate_per_M` from `model-catalog.txt`
3. Legacy blended: `price_per_1k` (converted × 1000 to per-M, used for both token types)
4. Hardcoded default: 3 per-M input, 15 per-M output (Sonnet-class fallback)

This means a developer who sets only `input_rate_per_1k` gets their custom input rate + the catalog output rate for the detected model — partial overrides work correctly without silent unit mixing.

---

## Decision 5: Report recomputes cost from stored token counts + model

**Decision**: `report-cost.sh` no longer uses the stored `cost_usd` field. For each ledger entry it:
1. Extracts `input_tokens`, `output_tokens`, and `model` from the JSONL record.
2. Resolves rates for that model using the same priority ladder as FR-004.
3. Computes a fresh cost in per-M units.
4. Displays this recomputed value in the Cost (USD) column.

**Rationale**: Allows correcting the catalog or config and seeing updated cost immediately without replaying any workflow steps (SC-003).

**Backward compatibility**: Entries recorded with `model: unknown` fall through to the blended/default rate — same as the old behavior. No data migration required.

---

## Decision 6: Cumulative column implementation

**Decision**: `report-cost.sh` maintains a running `cumulative_cost` accumulator (initialized to 0, per-M internal units). After computing each row's recomputed cost, it adds it to the accumulator and prints both the row cost and cumulative total as 4dp USD values.

**Format**: New column header "Cumulative" appended to the existing table. The grand total line below the table continues to appear and is derived from the final cumulative value (not a separate summation).

---

## Catalog Data Sources

### Claude models — authoritative source: wibey-cli `src/constants/models.ts`

Internal Walmart pricing (via Wibey gateway) differs from public Anthropic list prices.  
**These are the gateway rates used by the Wibey harness, not the public API rates.**

| Model ID | Input ($/M) | Output ($/M) | Notes |
|---|---|---|---|
| claude-opus-4-8 | 5 | 25 | Same rate card as Opus 4.6 |
| claude-opus-4-6 | 5 | 25 | |
| claude-sonnet-5 | 3 | 15 | |
| claude-sonnet-4-6 | 3 | 15 | Default model in Wibey |
| claude-sonnet-4-5-20250929 | 3 | 15 | |
| claude-sonnet-4-20250514 | 3 | 15 | |
| claude-haiku-4-5-20251001 | 1 | 5 | |

**Excluded**: `auto-elite`, `auto-economy` — virtual model IDs that resolve to executor models at the harness level. The harness injects the executor's real model ID into the session context, so catalog lookup naturally resolves to the executor's price.

### OpenAI models — authoritative source: openai.com/api/pricing (fetched 2026-07-13)

⚠️ **Important**: The Wibey gateway (`wibey-gateway.prod.walmart.com/passthrough/anthropic`) routes to Anthropic only. OpenAI models are NOT auto-detected via the harness in the current Walmart setup. These catalog entries support manual cost recording (e.g., a developer who uses the OpenAI API directly and calls `speckit.cost.record` with `--model gpt-5.4`).

Live pricing as of 2026-07-13 (standard tier, text modality):

| Model ID | Input ($/M) | Output ($/M) | Notes |
|---|---|---|---|
| gpt-5.6-sol | 5.00 | 30.00 | Flagship |
| gpt-5.6-terra | 2.50 | 15.00 | Flagship mid |
| gpt-5.6-luna | 1.00 | 6.00 | Flagship economy |
| gpt-5.5 | 5.00 | 30.00 | |
| gpt-5.5-pro | 30.00 | 180.00 | Premium |
| gpt-5.4 | 2.50 | 15.00 | |
| gpt-5.4-mini | 0.75 | 4.50 | |
| gpt-5.4-nano | 0.20 | 1.25 | |
| gpt-5.4-pro | 30.00 | 180.00 | Premium |
| o4-mini-2025-04-16 | 4.00 | 16.00 | Fine-tuning inference |

**Not found on live page**: classic `gpt-4o`, `o1`, `o3-mini` (superseded as of July 2026).

---

## Files to Create / Modify

| File | Action | Purpose |
|---|---|---|
| `scripts/bash/lib/catalog.sh` | CREATE | Catalog lookup library (pure bash) |
| `model-catalog.txt` | CREATE | Flat-text model price catalog |
| `scripts/bash/record-cost.sh` | MODIFY | Add `--model` flag; catalog rate resolution |
| `scripts/bash/report-cost.sh` | MODIFY | Recompute from model+catalog; add cumulative column |
| `scripts/bash/lib/config.sh` | MODIFY | Add `input_rate_per_1k`, `output_rate_per_1k` reader; normalize units |
| `commands/speckit.cost.record.md` | MODIFY | AI instructions: extract model from harness context; pass `--model` |
| `config-template.yml` | MODIFY | Document new config keys |
| `extension.yml` | MODIFY | Declare catalog file in provides.config; add new config defaults |
