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
#     [--provider P] [--note "..."]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
step=""
in_chars=""
out_chars=""
in_tokens=""
out_tokens=""
provider_override=""
note=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)        step="$2";              shift 2 ;;
    --in-chars)    in_chars="$2";          shift 2 ;;
    --out-chars)   out_chars="$2";         shift 2 ;;
    --in-tokens)   in_tokens="$2";         shift 2 ;;
    --out-tokens)  out_tokens="$2";        shift 2 ;;
    --provider)    provider_override="$2"; shift 2 ;;
    --note)        note="$2";              shift 2 ;;
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

# ── Config values (CR-R2) ────────────────────────────────────────────────────
price_per_1k="$(config_get price_per_1k)"
[[ -z "$price_per_1k" ]] && price_per_1k="0.003"
# Validate price_per_1k is numeric before awk (FIXED high: awk injection via config).
[[ "$price_per_1k" =~ ^[0-9]+(\.[0-9]+)?$ ]] || price_per_1k="0.003"
model="$(config_get model)"
[[ -z "$model" ]] && model="unknown"

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

# ── Cost computation (CR-R4, R2) ─────────────────────────────────────────────
# FIXED (high): use awk -v to pass all values — prevents shell injection,
# and || _fail ensures FR-015 non-blocking contract under set -euo pipefail.
cost_usd="$(awk -v i="$in_tokens" -v o="$out_tokens" -v p="$price_per_1k" \
  'BEGIN { printf "%.6f", (i + o) / 1000 * p }')" \
  || _fail "could not compute cost_usd"

# ── Ledger directory and file (CR-R5, §II) ───────────────────────────────────
ledger_dir="$(config_get_ledger_dir)"
ledger="$(config_get_ledger_path)"
mkdir -p "$ledger_dir" || _fail "could not create ledger directory '$ledger_dir'"

# ── Emit JSONL record (CR-R5, FR-003, FR-018) ────────────────────────────────
record="$(jsonl_emit \
  --step          "$step" \
  --spec          "$spec" \
  --provider      "$provider" \
  --input_tokens  "$in_tokens" \
  --output_tokens "$out_tokens" \
  --model         "$model" \
  --cost_usd      "$cost_usd" \
  --note          "$note")" \
  || _fail "could not assemble JSONL record"

printf '%s\n' "$record" >> "$ledger" || _fail "could not append to ledger '$ledger'"

# ── Inline summary (CR-R6, FR-002, SC-001) ───────────────────────────────────
# Display step name without "after_" prefix (data-model.md §step storage vs display).
display_step="${step#after_}"
# FIXED (high): use awk -v to pass cost_usd safely.
display_cost="$(awk -v c="$cost_usd" 'BEGIN { printf "%.4f", c }')" \
  || display_cost="$cost_usd"
printf '💰 %s: ~%s in / ~%s out tokens ≈ $%s\n' \
  "$display_step" "$in_tokens" "$out_tokens" "$display_cost"
