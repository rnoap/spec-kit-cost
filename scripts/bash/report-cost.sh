#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# report-cost.sh — Read-only per-spec cost breakdown report.
#
# Reads .specify/extensions/cost/cost-ledger.jsonl, filters to the current spec,
# recomputes cost from stored token counts + model using the current catalog/config rates,
# renders a markdown breakdown table with a Cumulative column, and prints a grand total.
# Never writes to the ledger (FR-010, §IV).
#
# Usage:
#   report-cost.sh [--spec <feature-dir-name>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/catalog.sh
source "${SCRIPT_DIR}/lib/catalog.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
spec_override=""
model_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec)  spec_override="$2";  shift 2 ;;
    --model) model_override="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── Resolve spec identifier (CR-P1, FR-004) ───────────────────────────────────
spec=""
if [[ -n "$spec_override" ]]; then
  spec="$spec_override"
else
  feature_json=".specify/feature.json"
  if [[ -f "$feature_json" ]]; then
    feature_json_line="$(tr -d '\n\r' < "$feature_json")"
    feature_dir="$(jsonl_get_field feature_directory "$feature_json_line")"
    [[ -z "$feature_dir" ]] && feature_dir="$(jsonl_get_field feature_dir "$feature_json_line")"
    spec="$(basename "$feature_dir")"
  fi
fi

if [[ -z "$spec" ]]; then
  printf 'speckit-cost: could not determine current spec. Pass --spec <name> or ensure .specify/feature.json exists.\n' >&2
  exit 1
fi

# ── Read ledger ───────────────────────────────────────────────────────────────
ledger="$(config_get_ledger_path)"

if [[ ! -f "$ledger" ]]; then
  printf 'No cost data recorded for this spec.\n'
  exit 0
fi

# ── Filter entries for current spec (CR-P2, SC-004) ──────────────────────────
entries=()
while IFS= read -r line; do
  entries+=("$line")
done < <(grep -F "\"spec\":\"${spec}\"" "$ledger" 2>/dev/null || true)

if [[ ${#entries[@]} -eq 0 ]]; then
  printf 'No cost data recorded for this spec.\n'
  exit 0
fi

# ── FR-004 rate resolution helpers ────────────────────────────────────────────
# Rate resolution — same FR-004 ladder also in record-cost.sh. Update both if FR-004 changes.
# Config values are per-1K; multiply ×1000 to convert to per-M.
# Reads config keys once (not per-entry) for efficiency.
_cfg_input_per_1k="$(config_get_input_rate_per_1k)"
_cfg_output_per_1k="$(config_get_output_rate_per_1k)"
# Legacy blended rate — only honored when explicitly set in the config file.
_cfg_blended="$(config_get_price_per_1k_raw)"
[[ "$_cfg_blended" =~ ^[0-9]+(\.[0-9]+)?$ ]] || _cfg_blended=""

# resolve_input_rate <model_id>
# Returns input rate in per-M; never empty (split default: $3/M).
resolve_input_rate() {
  local model_id="$1"
  # 1. Config override (per-1K → per-M via ×1000)
  if [[ -n "$_cfg_input_per_1k" && "$_cfg_input_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    awk -v r="$_cfg_input_per_1k" 'BEGIN { printf "%.9f", r * 1000 }'
    return
  fi
  # 2. Catalog rate for detected model (normalized matching via catalog.sh)
  local cat_in
  cat_in="$(catalog_get_input_rate "$model_id")"
  if [[ -n "$cat_in" ]]; then
    printf '%s' "$cat_in"
    return
  fi
  # 3. Legacy blended (per-1K → per-M) — only when explicitly configured
  if [[ -n "$_cfg_blended" ]]; then
    awk -v r="$_cfg_blended" 'BEGIN { printf "%.9f", r * 1000 }'
    return
  fi
  # 4. Split default (Sonnet-class input)
  printf '3'
}

# resolve_output_rate <model_id>
# Returns output rate in per-M; never empty (split default: $15/M).
resolve_output_rate() {
  local model_id="$1"
  # 1. Config override (per-1K → per-M)
  if [[ -n "$_cfg_output_per_1k" && "$_cfg_output_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    awk -v r="$_cfg_output_per_1k" 'BEGIN { printf "%.9f", r * 1000 }'
    return
  fi
  # 2. Catalog rate for detected model (normalized matching via catalog.sh)
  local cat_out
  cat_out="$(catalog_get_output_rate "$model_id")"
  if [[ -n "$cat_out" ]]; then
    printf '%s' "$cat_out"
    return
  fi
  # 3. Legacy blended (per-1K → per-M) — only when explicitly configured
  if [[ -n "$_cfg_blended" ]]; then
    awk -v r="$_cfg_blended" 'BEGIN { printf "%.9f", r * 1000 }'
    return
  fi
  # 4. Split default (Sonnet-class output)
  printf '15'
}

# resolve_cache_read_rate <model_id> <input_rate_M>
# Returns cache-read rate in per-M: explicit catalog field, else derived 0.10x
# the resolved input rate (data-model.md; ladder duplicated with record-cost.sh).
resolve_cache_read_rate() {
  local model_id="$1" input_rate="$2"
  local cat_cr
  cat_cr="$(catalog_get_cache_read_rate "$model_id")"
  if [[ -n "$cat_cr" ]]; then
    printf '%s' "$cat_cr"
    return
  fi
  awk -v r="$input_rate" 'BEGIN { printf "%.9f", r * 0.10 }'
}

# resolve_cache_write_rate <model_id> <input_rate_M>
# Returns cache-write rate in per-M: explicit catalog field, else derived 1.25x
# the resolved input rate (data-model.md; ladder duplicated with record-cost.sh).
resolve_cache_write_rate() {
  local model_id="$1" input_rate="$2"
  local cat_cw
  cat_cw="$(catalog_get_cache_write_rate "$model_id")"
  if [[ -n "$cat_cw" ]]; then
    printf '%s' "$cat_cw"
    return
  fi
  awk -v r="$input_rate" 'BEGIN { printf "%.9f", r * 1.25 }'
}

# ── Render breakdown table (CR-P3, FR-008, FR-009) ───────────────────────────
printf '## Cost Report: %s\n\n' "$spec"
printf '| Step | Src | Tokens | Cost (USD) | Cumulative |\n'
printf '|------|:---:|-------:|-----------:|-----------:|\n'

cumulative="0"

for entry in "${entries[@]}"; do
  step="$(jsonl_get_field step "$entry")"
  display_step="${step#after_}"
  in_tok="$(jsonl_get_field input_tokens "$entry")"
  out_tok="$(jsonl_get_field output_tokens "$entry")"
  # T012: extract model from each ledger entry (FR-008)
  entry_model="$(jsonl_get_field model "$entry")"
  [[ -z "$entry_model" ]] && entry_model="unknown"

  # --model flag overrides per-entry model for rate resolution (what-if repricing)
  rate_model="${model_override:-$entry_model}"

  # T009: cache fields — absent ⇒ 0 (contracts/ledger-schema.md reader rule)
  cache_read_tok="$(jsonl_get_field cache_read_tokens "$entry")"
  cache_write_tok="$(jsonl_get_field cache_write_tokens "$entry")"
  [[ -z "$cache_read_tok"  ]] && cache_read_tok=0
  [[ -z "$cache_write_tok" ]] && cache_write_tok=0

  # Src column: 'm' when source=measured, else 'e' (contracts/ledger-schema.md)
  entry_source="$(jsonl_get_field source "$entry")"
  src_marker="e"
  [[ "$entry_source" == "measured" ]] && src_marker="m"

  # T013/T009: recompute cost from token counts + model rates (four-term formula;
  # ignore stored cost_usd). fresh_in floors at 0 (anomaly-safe, mirrors record-cost.sh).
  fresh_in="$(awk -v i="$in_tok" -v cr="$cache_read_tok" -v cw="$cache_write_tok" \
    'BEGIN { f = i - cr - cw; if (f < 0) f = 0; printf "%d", f }')"

  input_rate_M="$(resolve_input_rate "$rate_model")"
  output_rate_M="$(resolve_output_rate "$rate_model")"
  cache_read_rate_M="$(resolve_cache_read_rate "$rate_model" "$input_rate_M")"
  cache_write_rate_M="$(resolve_cache_write_rate "$rate_model" "$input_rate_M")"
  cost_raw="$(awk -v fi="$fresh_in" -v cr="$cache_read_tok" -v cw="$cache_write_tok" -v o="$out_tok" \
                  -v ir="$input_rate_M" -v crr="$cache_read_rate_M" -v cwr="$cache_write_rate_M" -v or_="$output_rate_M" \
    'BEGIN { printf "%.6f", (fi * ir / 1000000) + (cr * crr / 1000000) + (cw * cwr / 1000000) + (o * or_ / 1000000) }')"

  # T014: accumulate cumulative running total
  cumulative="$(awk -v t="$cumulative" -v c="$cost_raw" 'BEGIN { printf "%.6f", t + c }')"

  cost_4dp="$(awk -v c="$cost_raw" 'BEGIN { printf "%.4f", c }')"
  cumulative_4dp="$(awk -v c="$cumulative" 'BEGIN { printf "%.4f", c }')"

  # T010: Tokens cell — "in (cached)/out" when cache counts present, else "in/out"
  cached_total="$(awk -v cr="$cache_read_tok" -v cw="$cache_write_tok" 'BEGIN { printf "%d", cr + cw }')"
  if [[ "$cached_total" -gt 0 ]]; then
    tokens_cell="${in_tok} (${cached_total} cached)/${out_tok}"
  else
    tokens_cell="${in_tok}/${out_tok}"
  fi

  # T015: render row with Src, Tokens, Cost, Cumulative columns
  printf '| %-12s | %-3s | %-22s | %10s | %10s |\n' \
    "$display_step" "$src_marker" "$tokens_cell" "\$$cost_4dp" "\$$cumulative_4dp"
done

# ── Grand total (FR-010) — derived from final cumulative value ─────────────────
total_4dp="$(awk -v t="$cumulative" 'BEGIN { printf "%.4f", t }')"
printf '\n**Total: $%s** (%d step(s))\n' "$total_4dp" "${#entries[@]}"
