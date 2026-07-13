#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# config.sh — Flat YAML key reader with documented defaults.
# Reads a key: value pair from cost-config.yml using grep/sed.
# Falls back to hardcoded defaults when the file or key is absent.
# Constitution §V: no external parser (no python-yaml, no yq).

# Default values (FR-011, FR-012, FR-014, data-model.md).
COST_DEFAULT_PROVIDER="self-report"
COST_DEFAULT_PRICE_PER_1K="0.003"
COST_DEFAULT_MODEL="unknown"

# config_get <key> [config_file]
# Read a flat YAML "key: value" pair from cost-config.yml.
# Returns the raw string value, trimmed of leading/trailing whitespace.
# Falls back to the hardcoded default for the given key if absent.
config_get() {
  local key="$1"
  local config_file="${2:-.specify/extensions/cost/cost-config.yml}"
  local value=""

  if [[ -f "$config_file" ]]; then
    # Match lines of the form:  key: value  (ignoring leading whitespace and comments)
    value="$(grep -E "^[[:space:]]*${key}[[:space:]]*:" "$config_file" 2>/dev/null \
      | head -1 \
      | sed "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*//" \
      | sed 's/[[:space:]]*$//' \
      | sed "s/^['\"]//; s/['\"]$//")"
  fi

  if [[ -z "$value" ]]; then
    # Return documented default.
    case "$key" in
      provider)     value="$COST_DEFAULT_PROVIDER" ;;
      price_per_1k) value="$COST_DEFAULT_PRICE_PER_1K" ;;
      model)        value="$COST_DEFAULT_MODEL" ;;
      *)            value="" ;;
    esac
  fi

  printf '%s' "$value"
}

# config_get_ledger_dir
# Return the directory where the ledger and config live.
# Always under .specify/extensions/cost/ (Constitution §II).
config_get_ledger_dir() {
  printf '%s' ".specify/extensions/cost"
}

# config_get_ledger_path
# Return the absolute ledger file path.
config_get_ledger_path() {
  printf '%s' ".specify/extensions/cost/cost-ledger.jsonl"
}
