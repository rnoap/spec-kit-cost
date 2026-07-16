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

# _catalog_rows
# Internal: emit "id|input|output" rows with comments/blanks stripped and
# fields trimmed. Uses awk field comparison — no regex injection possible.
_catalog_rows() {
  [[ -f "$CATALOG_FILE" ]] || return 0
  awk -F'|' '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    NF >= 3 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      print $1 "|" $2 "|" $3
    }
  ' "$CATALOG_FILE" 2>/dev/null
}

# _catalog_exact_row <model_id>
# Internal: return the "input|output" fields for an exact-ID match, or "".
_catalog_exact_row() {
  local model_id="$1"
  _catalog_rows | awk -F'|' -v id="$model_id" '$1 == id { print $2 "|" $3; exit }'
}

# catalog_normalize_model <raw>
# Normalize a model label toward a canonical catalog ID:
#   - strips a trailing parenthetical ("GPT-5.3-Codex (Preview)" → "GPT-5.3-Codex")
#   - lowercases
#   - trims whitespace; converts inner spaces/underscores to dashes
#   - collapses repeated dashes and trims edge dashes
catalog_normalize_model() {
  local m="$1"
  m="${m%%(*}"
  m="$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')"
  m="$(printf '%s' "$m" | sed -e 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        -e 's/[[:space:]_]/-/g' -e 's/--*/-/g' -e 's/^-//; s/-$//')"
  printf '%s' "$m"
}

# catalog_resolve_model <raw>
# Resolve a raw model label to the canonical catalog ID, or "" if no match.
# Matching ladder (first hit wins):
#   1. Exact ID as given.
#   2. Normalized (lowercase, spaces→dashes) — handles UI labels like "GPT-5.3-Codex".
#   3. Normalized with dots→dashes — handles "Claude Sonnet 4.6" → claude-sonnet-4-6.
#   4. Longest catalog ID that is a dash-boundary prefix of the candidate —
#      handles dated/suffixed variants like claude-sonnet-4-6-20260101.
catalog_resolve_model() {
  local raw="$1"
  [[ -z "$raw" || "$raw" == "unknown" ]] && return 0
  [[ -f "$CATALOG_FILE" ]] || return 0

  if [[ -n "$(_catalog_exact_row "$raw")" ]]; then
    printf '%s' "$raw"
    return 0
  fi

  local norm dotless
  norm="$(catalog_normalize_model "$raw")"
  [[ -z "$norm" ]] && return 0
  if [[ -n "$(_catalog_exact_row "$norm")" ]]; then
    printf '%s' "$norm"
    return 0
  fi

  dotless="${norm//./-}"
  if [[ "$dotless" != "$norm" && -n "$(_catalog_exact_row "$dotless")" ]]; then
    printf '%s' "$dotless"
    return 0
  fi

  local best="" id rest
  while IFS='|' read -r id rest; do
    [[ -z "$id" ]] && continue
    if [[ "$norm" == "$id"-* || "$dotless" == "$id"-* ]]; then
      (( ${#id} > ${#best} )) && best="$id"
    fi
  done < <(_catalog_rows)
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

# _catalog_validate_rate <value>
# Returns 0 if value is a non-negative number (integer or decimal), 1 otherwise.
_catalog_validate_rate() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

# catalog_get_rates <model_id>
# Returns "input_per_M|output_per_M" for the model, or "" if not found or invalid.
# Applies the catalog_resolve_model matching ladder (case/format-insensitive).
# Emits a warning to stderr if the row exists but contains non-numeric rates.
catalog_get_rates() {
  local model_id="$1"
  local resolved row
  resolved="$(catalog_resolve_model "$model_id")"
  [[ -z "$resolved" ]] && return 0
  row="$(_catalog_exact_row "$resolved")"
  [[ -z "$row" ]] && return 0

  local in_rate out_rate
  in_rate="$(printf '%s' "$row" | cut -d'|' -f1)"
  out_rate="$(printf '%s' "$row" | cut -d'|' -f2)"

  if ! _catalog_validate_rate "$in_rate" || ! _catalog_validate_rate "$out_rate"; then
    printf '⚠️  speckit-cost catalog: invalid rate for model "%s" (got "%s|%s") — skipping\n' \
      "$resolved" "$in_rate" "$out_rate" >&2
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
