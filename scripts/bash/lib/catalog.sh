#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# catalog.sh — Model price catalog lookup library.
# Reads .specify/extensions/cost/model-catalog.txt using only POSIX utilities.
# Constitution §V: Shell-First, Zero Runtime Dependencies.
#
# Format: model-id|input_per_M_USD|output_per_M_USD
# Rates are in USD per million tokens.
#
# Rate resolution — same FR-004 ladder also in record-cost.sh and report-cost.sh.
# Update model-catalog.txt to change prices; no changes to this file required.

# CATALOG_FILE: default path; override via SPECKIT_COST_CATALOG env var (for testing).
CATALOG_FILE="${SPECKIT_COST_CATALOG:-.specify/extensions/cost/model-catalog.txt}"

# _catalog_find_row <model_id>
# Internal: return the raw "input|output" fields for a model, or empty string.
_catalog_find_row() {
  local model_id="$1"
  local catalog="${CATALOG_FILE}"

  [[ -f "$catalog" ]] || return 0

  # Strip comment lines and blank lines, then find the first exact match.
  # FIXED: use grep -F for literal matching to prevent BRE metachar injection.
  grep -v '^[[:space:]]*#' "$catalog" 2>/dev/null \
    | grep -v '^[[:space:]]*$' \
    | grep -m 1 -F "${model_id}|" \
    | grep "^${model_id}|" \
    | cut -d'|' -f2-3
}

# _catalog_validate_rate <value>
# Returns 0 if value is a non-negative number (integer or decimal), 1 otherwise.
_catalog_validate_rate() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# catalog_get_rates <model_id>
# Returns "input_per_M|output_per_M" for the model, or "" if not found or invalid.
# Emits a warning to stderr if the row exists but contains non-numeric rates.
catalog_get_rates() {
  local model_id="$1"
  local row
  row="$(_catalog_find_row "$model_id")"
  [[ -z "$row" ]] && return 0

  local in_rate out_rate
  in_rate="$(printf '%s' "$row" | cut -d'|' -f1)"
  out_rate="$(printf '%s' "$row" | cut -d'|' -f2)"

  if ! _catalog_validate_rate "$in_rate" || ! _catalog_validate_rate "$out_rate"; then
    printf '⚠️  speckit-cost catalog: invalid rate for model "%s" (got "%s|%s") — skipping\n' \
      "$model_id" "$in_rate" "$out_rate" >&2
    return 0
  fi

  printf '%s|%s' "$in_rate" "$out_rate"
}

# catalog_get_input_rate <model_id>
# Returns the input_per_M float, or "" if model not in catalog.
catalog_get_input_rate() {
  local rates
  rates="$(catalog_get_rates "$1")"
  [[ -z "$rates" ]] && return 0
  printf '%s' "$rates" | cut -d'|' -f1
}

# catalog_get_output_rate <model_id>
# Returns the output_per_M float, or "" if model not in catalog.
catalog_get_output_rate() {
  local rates
  rates="$(catalog_get_rates "$1")"
  [[ -z "$rates" ]] && return 0
  printf '%s' "$rates" | cut -d'|' -f2
}
