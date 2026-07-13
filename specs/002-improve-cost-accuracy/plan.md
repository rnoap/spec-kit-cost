# Implementation Plan: Accurate Model-Aware Cost Calculation and Cumulative Report Table

**Branch**: `002-improve-cost-accuracy` | **Date**: 2026-07-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-improve-cost-accuracy/spec.md`

---

## Summary

Replace the extension's single blended-rate cost model with a two-rate (input/output) per-model pricing catalog. The catalog ships pre-populated with all Wibey-supported Claude models (rates from wibey-cli `src/constants/models.ts`) and widely-used OpenAI models (rates from openai.com/api/pricing, verified 2026-07-13). The model active during each workflow step is detected automatically from the Wibey harness-injected session context. The cost report is updated to recompute costs at display time from stored token counts + stored model ID, and gains a Cumulative running-total column.

---

## Technical Context

**Language/Version**: Bash (POSIX-compatible) — same as existing extension scripts

**Primary Dependencies**: POSIX standard utilities only: `awk`, `grep`, `sed`, `cut`, `date`, `printf`, `mktemp`, `wc` — no external runtime required (Constitution §V)

**Storage**: `.specify/extensions/cost/cost-ledger.jsonl` (append-only JSONL, unchanged schema v1); `.specify/extensions/cost/model-catalog.txt` (new flat-text catalog); `.specify/extensions/cost/cost-config.yml` (optional config, backward-compatible)

**Testing**: Manual shell execution against the ledger (no test framework in this extension). Validation scenarios in [quickstart.md](quickstart.md).

**Target Platform**: macOS and Linux (POSIX shell)

**Project Type**: spec-kit extension (hook-based bash scripts + AI command markdown files)

**Performance Goals**: All hook scripts must exit in <2 seconds (non-blocking contract, FR-011). Catalog lookup is a single `grep -m 1` — O(n) lines, negligible for the expected catalog size (<100 entries).

**Constraints**: No external runtime dependencies. No writes outside `.specify/extensions/cost/`. All hook scripts exit 0 on any failure. Config parsing uses only `grep`/`sed` (Constitution §V).

**Scale/Scope**: Catalog initial size ~17 entries (7 Claude + 10 OpenAI). Max expected ledger size: hundreds of entries per project lifetime.

---

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| §I Extension Contract First | ✅ PASS | `extension.yml` will be updated in the same change that adds `model-catalog.txt` and new config keys. |
| §II Non-Destructive Tracking | ✅ PASS | All new writes are to `model-catalog.txt` (new file under `.specify/extensions/cost/`) and to the existing ledger. No writes to `specs/`, `AGENTS.md`, or project source files. |
| §III Pluggable Data Source | ✅ PASS | Catalog lookup is a new resolution layer inside the existing provider switch. Existing providers unchanged. |
| §IV Append-Only Ledger | ✅ PASS | No changes to ledger format. The `model` field (already in schema v1) is now populated from harness context rather than static config. Schema version stays at `"v": 1`. |
| §V Shell-First, Zero Runtime Dependencies | ✅ PASS | Catalog uses pipe-delimited format parseable with `grep`/`cut`. New `lib/catalog.sh` uses only POSIX utilities. No Python, Node.js, jq, or yq. |

**Complexity Tracking**: No violations — table omitted.

---

## Project Structure

### Documentation (this feature)

```text
specs/002-improve-cost-accuracy/
├── spec.md
├── plan.md              ← this file
├── research.md          ← Phase 0 (complete)
├── data-model.md        ← Phase 1 (complete)
├── contracts/
│   ├── catalog-format.md   ← Phase 1 (complete)
│   └── config-schema.md    ← Phase 1 (complete)
├── quickstart.md        ← Phase 1 (complete)
├── checklists/
│   └── requirements.md
└── tasks.md             ← Phase 2 (/speckit-tasks)
```

### Source Code Changes

```text
.specify/extensions/cost/
├── model-catalog.txt                      ← CREATE (flat-text model price catalog)
├── extension.yml                          ← MODIFY (declare catalog in provides.config)
├── config-template.yml                    ← MODIFY (document new config keys)
├── commands/
│   └── speckit.cost.record.md             ← MODIFY (model detection from harness context)
└── scripts/bash/
    ├── lib/
    │   ├── catalog.sh                     ← CREATE (catalog lookup library)
    │   ├── config.sh                      ← MODIFY (add new config key readers + unit norm)
    │   └── json.sh                        ← no change
    ├── record-cost.sh                     ← MODIFY (--model flag, catalog rate resolution)
    ├── report-cost.sh                     ← MODIFY (cumulative column, recompute from model)
    └── reset-cost.sh                      ← no change
```

**Structure Decision**: The extension follows its existing single-directory layout under `.specify/extensions/cost/`. The catalog file sits alongside `cost-config.yml` and `cost-ledger.jsonl` — all managed state for this extension. The new `lib/catalog.sh` follows the same pattern as `lib/config.sh` and `lib/json.sh`.

---

## Implementation Specification

### 1. `model-catalog.txt` (NEW)

Pipe-delimited flat text. See [contracts/catalog-format.md](contracts/catalog-format.md).

Full initial content:

```text
# spec-kit-cost model price catalog
# Format: model-id|input_per_M_USD|output_per_M_USD
# All rates in USD per million tokens.
#
# Claude rates: wibey-cli src/constants/models.ts (Walmart gateway — not public list prices)
# OpenAI rates: openai.com/api/pricing (verified 2026-07-13)
#
# NOTE: The Wibey gateway routes Anthropic only. OpenAI entries support
#       manual recording (--model gpt-5.4) for developers using OpenAI directly.

# ── Claude models ────────────────────────────────────────────────────────────
claude-opus-4-8|5|25
claude-opus-4-6|5|25
claude-sonnet-5|3|15
claude-sonnet-4-6|3|15
claude-sonnet-4-5-20250929|3|15
claude-sonnet-4-20250514|3|15
claude-haiku-4-5-20251001|1|5

# ── OpenAI models ─────────────────────────────────────────────────────────────
gpt-5.6-sol|5|30
gpt-5.6-terra|2.5|15
gpt-5.6-luna|1|6
gpt-5.5|5|30
gpt-5.5-pro|30|180
gpt-5.4|2.5|15
gpt-5.4-mini|0.75|4.5
gpt-5.4-nano|0.2|1.25
gpt-5.4-pro|30|180
o4-mini-2025-04-16|4|16
```

---

### 2. `lib/catalog.sh` (NEW)

Pure-bash catalog lookup library. Sourced by `record-cost.sh` and `report-cost.sh`.

Key functions:

```bash
# catalog_get_rates <model_id>
# Returns "input_per_M|output_per_M" for the model, or "" if not found.
# Uses grep -m 1 for first-match semantics (O(n), POSIX).

# catalog_get_input_rate <model_id>
# Returns the input_per_M float, or "" if model not in catalog.

# catalog_get_output_rate <model_id>
# Returns the output_per_M float, or "" if model not in catalog.

# CATALOG_FILE default: .specify/extensions/cost/model-catalog.txt
# Override via SPECKIT_COST_CATALOG env var (for testing).
```

Validation: if `input_per_M` or `output_per_M` is not numeric (`[0-9]+(\.[0-9]+)?`), the entry is skipped and a warning is emitted to stderr. The function returns "".

---

### 3. `lib/config.sh` (MODIFY)

Add readers for two new config keys:

```bash
# config_get_input_rate_per_1k → float or ""
# config_get_output_rate_per_1k → float or ""
```

These follow the same `grep`/`sed` pattern as `config_get`. No changes to `config_get`, `config_get_ledger_dir`, or `config_get_ledger_path`.

---

### 4. `record-cost.sh` (MODIFY)

**Add `--model` argument**:
```bash
model_override=""
# in arg parse:
--model) model_override="$2"; shift 2 ;;
```

**Rate resolution** (after all args parsed, after provider resolution):

```bash
# Resolve active model (harness-detected takes priority over config label)
active_model="${model_override:-$(config_get model)}"
active_model="${active_model:-unknown}"

# Resolve input rate (per-M, normalized from per-1K config if needed)
cfg_input_rate="$(config_get_input_rate_per_1k)"
cfg_output_rate="$(config_get_output_rate_per_1k)"
cfg_blended="$(config_get price_per_1k)"; [[ -z "$cfg_blended" ]] && cfg_blended="0.003"

catalog_rates="$(catalog_get_rates "$active_model")"
catalog_in=""
catalog_out=""
if [[ -n "$catalog_rates" ]]; then
  catalog_in="$(printf '%s' "$catalog_rates" | cut -d'|' -f1)"
  catalog_out="$(printf '%s' "$catalog_rates" | cut -d'|' -f2)"
elif [[ "$active_model" != "unknown" ]]; then
  printf '⚠️  speckit-cost: model "%s" not found in catalog — using fallback rate\n' "$active_model" >&2
fi

# input_rate_M: per-M
if [[ -n "$cfg_input_rate" ]]; then
  input_rate_M="$(awk -v r="$cfg_input_rate" 'BEGIN { printf "%.6f", r * 1000 }')"
elif [[ -n "$catalog_in" ]]; then
  input_rate_M="$catalog_in"
else
  input_rate_M="$(awk -v r="$cfg_blended" 'BEGIN { printf "%.6f", r * 1000 }')"
fi

# output_rate_M: same pattern
if [[ -n "$cfg_output_rate" ]]; then
  output_rate_M="$(awk -v r="$cfg_output_rate" 'BEGIN { printf "%.6f", r * 1000 }')"
elif [[ -n "$catalog_out" ]]; then
  output_rate_M="$catalog_out"
else
  output_rate_M="$(awk -v r="$cfg_blended" 'BEGIN { printf "%.6f", r * 1000 }')"
fi

# cost_usd (per-M formula)
cost_usd="$(awk -v i="$in_tokens" -v o="$out_tokens" \
               -v ir="$input_rate_M" -v or_="$output_rate_M" \
  'BEGIN { printf "%.6f", (i * ir / 1000000) + (o * or_ / 1000000) }')" \
  || _fail "could not compute cost_usd"
```

Pass `--model "$active_model"` to `jsonl_emit`.

---

### 5. `speckit.cost.record.md` (MODIFY)

**Step 3 addition** (before gathering token counts):

> **Step 3a — Detect active model**
>
> Identify the current model from the Wibey harness-injected session context. The harness inserts a line of the form "Current model: <display-name> (<model-id>)" into the agent's system context. Extract the model ID in parentheses (e.g., `claude-sonnet-4-6`). If no such line is present, use the model label from `cost-config.yml`, or `unknown` if that is also absent.
>
> Pass the detected model ID as `--model <model-id>` to the bash script invocation below.

---

### 6. `report-cost.sh` (MODIFY)

**Source catalog.sh** at the top (alongside `config.sh` and `json.sh`).

**Rate resolution helper**: inline or sourced `resolve_input_rate` / `resolve_output_rate` functions following the same priority ladder as `record-cost.sh`.

**Per-entry processing** (replace current `cost_raw` read with recomputation):

```bash
for entry in "${entries[@]}"; do
  step="$(jsonl_get_field step "$entry")"
  display_step="${step#after_}"
  in_tok="$(jsonl_get_field input_tokens "$entry")"
  out_tok="$(jsonl_get_field output_tokens "$entry")"
  entry_model="$(jsonl_get_field model "$entry")"
  [[ -z "$entry_model" ]] && entry_model="unknown"

  # Resolve rates for this entry's model
  input_rate_M="$(resolve_input_rate "$entry_model")"
  output_rate_M="$(resolve_output_rate "$entry_model")"

  # Recompute cost from token counts + current rates
  cost_raw="$(awk -v i="$in_tok" -v o="$out_tok" \
                  -v ir="$input_rate_M" -v or_="$output_rate_M" \
    'BEGIN { printf "%.6f", (i * ir / 1000000) + (o * or_ / 1000000) }')"

  cost_4dp="$(awk -v c="$cost_raw" 'BEGIN { printf "%.4f", c }')"

  # Accumulate cumulative
  cumulative="$(awk -v t="$cumulative" -v c="$cost_raw" 'BEGIN { printf "%.6f", t + c }')"
  cumulative_4dp="$(awk -v c="$cumulative" 'BEGIN { printf "%.4f", c }')"

  printf '| %-12s | %12s | %13s | %10s | %10s |\n' \
    "$display_step" "$in_tok" "$out_tok" "\$$cost_4dp" "\$$cumulative_4dp"
done
```

**Table header** (add Cumulative column):
```
| Step | Input tokens | Output tokens | Cost (USD) | Cumulative |
|------|-------------:|--------------:|-----------:|-----------:|
```

**Grand total line** (unchanged format, value derived from final cumulative):
```bash
printf '\n**Total: $%s** (%d step(s))\n' "$cumulative_4dp" "${#entries[@]}"
```

---

### 7. `config-template.yml` (MODIFY)

Add documentation block for the new config keys after the `price_per_1k` entry:

```yaml
# input_rate_per_1k / output_rate_per_1k: separate per-type override rates.
#   When set, these take priority over the model catalog for their token type.
#   Use for unknown models or custom enterprise pricing.
#   If only one is set, the other resolves from the catalog (or price_per_1k).
#   Leave commented to use the auto-detected model catalog rate (recommended).
# input_rate_per_1k: 0.005
# output_rate_per_1k: 0.025
```

---

### 8. `extension.yml` (MODIFY)

Under `provides.config`, add the catalog:
```yaml
- name: "model-catalog.txt"
  description: "Pre-populated model price catalog (pipe-delimited: model-id|input_per_M|output_per_M)"
  required: false
```

Under `config.defaults`, add new keys:
```yaml
input_rate_per_1k: null   # absent by default; catalog takes priority
output_rate_per_1k: null  # absent by default; catalog takes priority
```

---

## Validation Scenarios

See [quickstart.md](quickstart.md) for runnable end-to-end scenarios covering:

1. Catalog lookup — Sonnet at expected rate
2. Premium model — Opus at higher rate
3. Manual override — config takes priority over catalog
4. Unknown model — graceful fallback with warning
5. Cumulative column — report table correctness
6. Backward compatibility — legacy blended config unchanged

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model ID format mismatch (harness injects display name, not API ID) | Medium | High | AI command extracts ID from parenthetical `(<model-id>)` in "Current model: <name> (<id>)" — validates against catalog; falls back gracefully if pattern not found. |
| OpenAI model IDs change (rolling updates) | High | Low | Catalog update is a single-file edit; no script changes required. Git history tracks versions. |
| `awk` numeric precision drift across platforms | Low | Low | All monetary values use `%.6f` storage and `%.4f` display. 4dp rounding is consistent. |
| Catalog file absent after fresh install | Low | High | `catalog_get_rates` returns `""` gracefully (file check at top). Warning emitted; fallback applies. |
