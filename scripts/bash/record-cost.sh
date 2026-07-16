#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# record-cost.sh — Record one Cost Entry for a completed spec-kit workflow step.
#
# Prints exactly one inline summary line to stdout:
#   💰 <step>: ~N in / ~N out tokens ≈ $N.NNNN
#
# On any failure: prints one warning to stderr and exits 0 (non-blocking, FR-015).
# Writes only under .specify/extensions/cost/ (Constitution §II).
#
# Usage:
#   record-cost.sh --step after_specify \
#     [--in-chars N] [--out-chars N]       # self-report: chars → tokens via ÷4
#     [--in-tokens N] [--out-tokens N]     # manual/log-file: direct token counts
#     [--cache-read-tokens N] [--cache-write-tokens N]  # cache-aware pricing (measured)
#     [--source measured|estimated]        # provenance marker (default: estimated)
#     [--provider P] [--note "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/catalog.sh
source "${SCRIPT_DIR}/lib/catalog.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
step=""
in_chars=""
out_chars=""
in_tokens=""
out_tokens=""
cache_read_tokens=""
cache_write_tokens=""
source_flag=""
provider_override=""
model_override=""
note=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)                step="$2";              shift 2 ;;
    --in-chars)            in_chars="$2";          shift 2 ;;
    --out-chars)           out_chars="$2";         shift 2 ;;
    --in-tokens)           in_tokens="$2";         shift 2 ;;
    --out-tokens)          out_tokens="$2";        shift 2 ;;
    --cache-read-tokens)   cache_read_tokens="$2"; shift 2 ;;
    --cache-write-tokens)  cache_write_tokens="$2"; shift 2 ;;
    --source)              source_flag="$2";        shift 2 ;;
    --provider)            provider_override="$2"; shift 2 ;;
    --model)               model_override="$2";    shift 2 ;;
    --note)                note="$2";               shift 2 ;;
    *) shift ;;
  esac
done

# ── Non-blocking error helper ─────────────────────────────────────────────────
_fail() {
  printf '⚠️  speckit-cost: %s — entry skipped\n' "$1" >&2
  exit 0  # Always exit 0: hooks must never block the workflow (FR-015, §II).
}

# ── Validate required --step argument ────────────────────────────────────────
[[ -z "$step" ]] && _fail "--step is required"

# Validate step is one of the seven supported events (FR-001).
case "$step" in
  after_specify|after_clarify|after_plan|after_tasks|after_analyze|after_checklist|after_implement) ;;
  *) _fail "unknown step '$step' (must be one of the seven after_* events)" ;;
esac

# ── Early numeric validation (FIXED high: prevents awk injection) ─────────────
# Validate in_chars and out_chars before any awk call.
# If they are set, they must be non-negative integers.
if [[ -n "$in_chars" ]] && [[ ! "$in_chars" =~ ^[0-9]+$ ]]; then
  _fail "--in-chars must be a non-negative integer, got: '$in_chars'"
fi
if [[ -n "$out_chars" ]] && [[ ! "$out_chars" =~ ^[0-9]+$ ]]; then
  _fail "--out-chars must be a non-negative integer, got: '$out_chars'"
fi

# ── Cache-aware flag validation (T006) ────────────────────────────────────────
# Cache flags must be non-negative integers when provided.
if [[ -n "$cache_read_tokens" ]] && [[ ! "$cache_read_tokens" =~ ^[0-9]+$ ]]; then
  _fail "--cache-read-tokens must be a non-negative integer, got: '$cache_read_tokens'"
fi
if [[ -n "$cache_write_tokens" ]] && [[ ! "$cache_write_tokens" =~ ^[0-9]+$ ]]; then
  _fail "--cache-write-tokens must be a non-negative integer, got: '$cache_write_tokens'"
fi

# --source accepts exactly 'measured' or 'estimated'.
if [[ -n "$source_flag" ]] && [[ "$source_flag" != "measured" && "$source_flag" != "estimated" ]]; then
  _fail "--source must be 'measured' or 'estimated', got: '$source_flag'"
fi
[[ -z "$source_flag" ]] && source_flag="estimated"

# Cache flags are incompatible with char mode — ambiguous usage (extends the
# existing mixed chars/tokens guard, contracts/record-cost-cli.md).
if { [[ -n "$cache_read_tokens" ]] || [[ -n "$cache_write_tokens" ]]; } && \
   { [[ -n "$in_chars" ]] || [[ -n "$out_chars" ]]; }; then
  _fail "--cache-read-tokens/--cache-write-tokens are incompatible with --in-chars/--out-chars (ambiguous usage). Use --in-tokens/--out-tokens instead."
fi

# ── Mixed --in-tokens / --out-chars guard (FIXED low: silent discard) ────────
if [[ -n "$in_tokens"  && -n "$out_chars"  && -z "$in_chars" ]] ||
   [[ -n "$in_chars"   && -n "$out_tokens" && -z "$out_chars" ]]; then
  _fail "mixed --in-tokens/--out-chars usage is ambiguous. Use either the --*-chars pair or the --*-tokens pair."
fi

# ── Provider resolution (CR-R1, §III) ────────────────────────────────────────
# Precedence: --provider flag → SPECKIT_COST_PROVIDER env → config file → default
provider="${provider_override:-${SPECKIT_COST_PROVIDER:-}}"
[[ -z "$provider" ]] && provider="$(config_get provider)"
[[ -z "$provider" ]] && provider="self-report"

# ── Active model resolution (FR-002) ─────────────────────────────────────────
# Precedence: --model flag (harness-detected by AI command) → config label → "unknown"
active_model="${model_override:-$(config_get model)}"
[[ -z "$active_model" ]] && active_model="unknown"

# ── Config rate values (FR-004, CR-R2) ───────────────────────────────────────
# Read optional per-type override keys (return "" when absent — no defaults here).
cfg_input_rate_per_1k="$(config_get_input_rate_per_1k)"
cfg_output_rate_per_1k="$(config_get_output_rate_per_1k)"
# Legacy blended fallback — only honored when explicitly set in the config file.
# When absent, the split defaults ($3/M input, $15/M output) apply instead.
price_per_1k="$(config_get_price_per_1k_raw)"
[[ "$price_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]] || price_per_1k=""

# ── Catalog lookup for detected model (FR-003, FR-005) ────────────────────────
# catalog_resolve_model normalizes UI labels (case, spaces, dots, dated suffixes)
# so "GPT-5.3-Codex" or "Claude Sonnet 4.6" resolve to their canonical IDs.
resolved_model="$(catalog_resolve_model "$active_model")"
catalog_rates=""
if [[ -n "$resolved_model" ]]; then
  catalog_rates="$(catalog_get_rates "$resolved_model")"
  # Store the canonical ID in the ledger so reports reprice correctly.
  active_model="$resolved_model"
fi
catalog_in=""
catalog_out=""
catalog_cache_read=""
catalog_cache_write=""
fallback_used=0
if [[ -n "$catalog_rates" ]]; then
  catalog_in="$(printf '%s' "$catalog_rates" | cut -d'|' -f1)"
  catalog_out="$(printf '%s' "$catalog_rates" | cut -d'|' -f2)"
  catalog_cache_read="$(printf '%s' "$catalog_rates" | cut -d'|' -f3)"
  catalog_cache_write="$(printf '%s' "$catalog_rates" | cut -d'|' -f4)"
elif [[ "$active_model" != "unknown" ]]; then
  # FR-005: emit non-fatal warning for unrecognized models; do not fail.
  fallback_used=1
  printf '⚠️  speckit-cost: model "%s" not found in catalog — using fallback rate. Add it to model-catalog.txt for accurate pricing.\n' \
    "$active_model" >&2
fi

# ── FR-004 rate resolution — per-M (USD per million tokens) ──────────────────
# Priority per token type: config override → catalog → explicit blended
# price_per_1k → split defaults ($3/M input, $15/M output — Sonnet-class).
# Config values are per-1K; multiply ×1000 to convert to per-M.
# Rate resolution — same ladder also in report-cost.sh. Update both if FR-004 changes.
if [[ -n "$cfg_input_rate_per_1k" && "$cfg_input_rate_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  input_rate_M="$(awk -v r="$cfg_input_rate_per_1k" 'BEGIN { printf "%.9f", r * 1000 }')"
elif [[ -n "$catalog_in" ]]; then
  input_rate_M="$catalog_in"
elif [[ -n "$price_per_1k" ]]; then
  input_rate_M="$(awk -v r="$price_per_1k" 'BEGIN { printf "%.9f", r * 1000 }')"
else
  input_rate_M="3"
fi

if [[ -n "$cfg_output_rate_per_1k" && "$cfg_output_rate_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  output_rate_M="$(awk -v r="$cfg_output_rate_per_1k" 'BEGIN { printf "%.9f", r * 1000 }')"
elif [[ -n "$catalog_out" ]]; then
  output_rate_M="$catalog_out"
elif [[ -n "$price_per_1k" ]]; then
  output_rate_M="$(awk -v r="$price_per_1k" 'BEGIN { printf "%.9f", r * 1000 }')"
else
  output_rate_M="15"
fi

# ── Cache-rate ladder (FR-001/FR-002, data-model.md) ──────────────────────────
# Catalog cache field → derived (0.10x read / 1.25x write) of the resolved
# input rate above. Rate resolution — same ladder also in report-cost.sh.
if [[ -n "$catalog_cache_read" ]]; then
  cache_read_rate_M="$catalog_cache_read"
else
  cache_read_rate_M="$(awk -v r="$input_rate_M" 'BEGIN { printf "%.9f", r * 0.10 }')"
fi

if [[ -n "$catalog_cache_write" ]]; then
  cache_write_rate_M="$catalog_cache_write"
else
  cache_write_rate_M="$(awk -v r="$input_rate_M" 'BEGIN { printf "%.9f", r * 1.25 }')"
fi

# ── Spec identifier from feature context (CR-R3, FR-004) ─────────────────────
feature_json=".specify/feature.json"
spec=""
if [[ -f "$feature_json" ]]; then
  feature_json_line="$(tr -d '\n\r' < "$feature_json")"
  feature_dir="$(jsonl_get_field feature_directory "$feature_json_line")"
  [[ -z "$feature_dir" ]] && feature_dir="$(jsonl_get_field feature_dir "$feature_json_line")"
  # FIXED (low): guard against empty feature_dir before calling basename.
  if [[ -n "$feature_dir" ]]; then
    spec="$(basename "$feature_dir")"
  fi
fi
[[ -z "$spec" ]] && _fail "could not determine spec identifier from .specify/feature.json"

# ── Token count resolution by provider ───────────────────────────────────────
case "$provider" in

  self-report)
    if [[ -n "$in_tokens" && -n "$out_tokens" ]]; then
      # Direct token counts supplied (e.g., from a wrapper that already computed them).
      : # use in_tokens / out_tokens as-is below
    elif [[ -n "$in_chars" || -n "$out_chars" ]]; then
      # chars ÷ 4 heuristic (FR-013, clarification §2026-07-13).
      # FIXED (high): use awk -v to pass variables safely (no shell interpolation).
      in_chars="${in_chars:-0}"
      out_chars="${out_chars:-0}"
      in_tokens="$(awk -v c="$in_chars" 'BEGIN { printf "%d", int((c + 3) / 4) }')" \
        || _fail "could not compute input token count"
      out_tokens="$(awk -v c="$out_chars" 'BEGIN { printf "%d", int((c + 3) / 4) }')" \
        || _fail "could not compute output token count"
    else
      _fail "self-report provider requires --in-chars/--out-chars or --in-tokens/--out-tokens"
    fi
    ;;

  manual)
    [[ -z "$in_tokens" || -z "$out_tokens" ]] && \
      _fail "manual provider requires --in-tokens and --out-tokens"
    ;;

  log-file)
    # v1.0.0 stub — log-file parsing is planned for v1.1 (FR-012, analysis finding I1).
    _fail "log-file provider is not yet implemented (planned for v1.1)"
    ;;

  *)
    _fail "unknown provider '$provider' (supported: self-report, manual, log-file)"
    ;;
esac

# Validate token counts are non-negative integers (data-model.md validation rules).
[[ "$in_tokens"  =~ ^[0-9]+$ ]] || _fail "input_tokens must be a non-negative integer"
[[ "$out_tokens" =~ ^[0-9]+$ ]] || _fail "output_tokens must be a non-negative integer"

# ── Cache-aware separation (T007, data-model.md) ─────────────────────────────
# fresh_in = total input minus the cache subsets, floored at 0. A floor means the
# host reported cache counts exceeding the input total (anomaly) — note it, but
# never fail (FR-013 non-blocking).
cache_read_tokens="${cache_read_tokens:-0}"
cache_write_tokens="${cache_write_tokens:-0}"

fresh_in="$(awk -v i="$in_tokens" -v cr="$cache_read_tokens" -v cw="$cache_write_tokens" \
  'BEGIN { f = i - cr - cw; if (f < 0) f = 0; printf "%d", f }')"

if awk -v i="$in_tokens" -v cr="$cache_read_tokens" -v cw="$cache_write_tokens" \
     'BEGIN { exit !(cr + cw > i) }'; then
  if [[ -n "$note" ]]; then
    note="${note}; anomaly: cache counts exceed input total"
  else
    note="anomaly: cache counts exceed input total"
  fi
fi

# ── Cost computation — four-term formula (FR-003, FR-004, data-model.md) ─────
# cost = ( fresh_in × input_rate_M + cache_read × cache_read_rate_M
#        + cache_write × cache_write_rate_M + output × output_rate_M ) / 1e6
# With both cache counts at 0, fresh_in == in_tokens, reducing exactly to the
# v1.3.0 two-term formula (SC-003 back-compat).
# awk -v flags prevent shell injection; || _fail satisfies FR-011 non-blocking contract.
cost_usd="$(awk -v fi="$fresh_in" -v cr="$cache_read_tokens" -v cw="$cache_write_tokens" -v o="$out_tokens" \
               -v ir="$input_rate_M" -v crr="$cache_read_rate_M" -v cwr="$cache_write_rate_M" -v or_="$output_rate_M" \
  'BEGIN { printf "%.6f", (fi * ir / 1000000) + (cr * crr / 1000000) + (cw * cwr / 1000000) + (o * or_ / 1000000) }')" \
  || _fail "could not compute cost_usd"

# ── Ledger directory and file (CR-R5, §II) ───────────────────────────────────
ledger_dir="$(config_get_ledger_dir)"
ledger="$(config_get_ledger_path)"
mkdir -p "$ledger_dir" || _fail "could not create ledger directory '$ledger_dir'"

# ── Emit JSONL record (CR-R5, FR-003, FR-018) ────────────────────────────────
record="$(jsonl_emit \
  --step                "$step" \
  --spec                "$spec" \
  --provider            "$provider" \
  --input_tokens        "$in_tokens" \
  --output_tokens       "$out_tokens" \
  --cache_read_tokens   "$cache_read_tokens" \
  --cache_write_tokens  "$cache_write_tokens" \
  --source              "$source_flag" \
  --model               "$active_model" \
  --cost_usd            "$cost_usd" \
  --note                "$note")" \
  || _fail "could not assemble JSONL record"

printf '%s\n' "$record" >> "$ledger" || _fail "could not append to ledger '$ledger'"

# ── Inline summary (CR-R6, FR-002, SC-001) ───────────────────────────────────
# Display step name without "after_" prefix (data-model.md §step storage vs display).
display_step="${step#after_}"
# FIXED (high): use awk -v to pass cost_usd safely.
display_cost="$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')" \
  || display_cost="$cost_usd"
# Make degraded accuracy visible inline when a *named* model missed the catalog
# (stderr warnings are often swallowed by agent harnesses).
fallback_suffix=""
if [[ "$fallback_used" -eq 1 ]]; then
  fallback_suffix=" (fallback rate — \"${active_model}\" not in catalog)"
fi

# T008: cache-aware summary additions — parenthetical when cached tokens were
# priced, "[measured]" when source=measured. Legacy path (both 0/estimated)
# renders byte-identical to v1.3.0 (SC-003).
cached_total="$(awk -v cr="$cache_read_tokens" -v cw="$cache_write_tokens" 'BEGIN { printf "%d", cr + cw }')"
cached_segment=""
[[ "$cached_total" -gt 0 ]] && cached_segment=" (${cached_total} cached)"

measured_suffix=""
[[ "$source_flag" == "measured" ]] && measured_suffix=" [measured]"

printf '💰 %s: ~%s in%s / ~%s out tokens ≈ $%s%s%s\n' \
  "$display_step" "$in_tokens" "$cached_segment" "$out_tokens" "$display_cost" "$measured_suffix" "$fallback_suffix"
