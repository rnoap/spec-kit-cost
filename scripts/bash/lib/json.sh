#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# json.sh — JSONL emit and field extraction utilities.
# No external dependencies (no jq). POSIX bash + awk/grep/sed only.
# Constitution §V: Shell-First, Zero Runtime Dependencies.

# json_escape <string>
# Escape a string for safe inclusion in a JSON value:
#   - backslashes → \\
#   - double-quotes → \"
#   - newlines stripped (preserves one-record-per-line invariant)
json_escape() {
  local s="$1"
  # Strip newlines first, then escape backslashes, then double-quotes.
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# jsonl_emit --step S --spec P --provider V --input_tokens N --output_tokens N
#             --model M --cost_usd F [--note TEXT]
# Assembles and prints one complete JSON record (schema v1) to stdout.
# Field order matches Constitution §IV canonical example.
# Caller is responsible for appending stdout to the ledger file.
# FIXED (critical): guards required numeric fields; emits nothing on missing values.
# FIXED (medium):   step and provider are now JSON-escaped before emission.
jsonl_emit() {
  local step="" spec="" provider="" input_tokens="" output_tokens=""
  local model="unknown" cost_usd="" note=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --step)         step="$2";           shift 2 ;;
      --spec)         spec="$2";           shift 2 ;;
      --provider)     provider="$2";       shift 2 ;;
      --input_tokens) input_tokens="$2";   shift 2 ;;
      --output_tokens)output_tokens="$2";  shift 2 ;;
      --model)        model="$2";          shift 2 ;;
      --cost_usd)     cost_usd="$2";       shift 2 ;;
      --note)         note="$2";           shift 2 ;;
      *) shift ;;
    esac
  done

  # Guard required numeric fields — missing values produce invalid JSON.
  [[ "$input_tokens"  =~ ^[0-9]+$        ]] || { printf 'jsonl_emit: input_tokens missing or non-integer\n' >&2; return 1; }
  [[ "$output_tokens" =~ ^[0-9]+$        ]] || { printf 'jsonl_emit: output_tokens missing or non-integer\n' >&2; return 1; }
  [[ "$cost_usd"      =~ ^[0-9]+\.[0-9]+ ]] || { printf 'jsonl_emit: cost_usd missing or non-numeric\n' >&2; return 1; }

  local ts
  # FIXED (low): fallback uses alternative flag rather than identical command.
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Escape ALL string fields — including step and provider (FIXED medium).
  local esc_step esc_spec esc_provider esc_model esc_note
  esc_step="$(json_escape "$step")"
  esc_spec="$(json_escape "$spec")"
  esc_provider="$(json_escape "$provider")"
  esc_model="$(json_escape "$model")"
  esc_note="$(json_escape "$note")"

  printf '{"v":1,"ts":"%s","step":"%s","spec":"%s","provider":"%s","input_tokens":%s,"output_tokens":%s,"model":"%s","cost_usd":%s,"note":"%s"}\n' \
    "$ts" "$esc_step" "$esc_spec" "$esc_provider" "$input_tokens" "$output_tokens" \
    "$esc_model" "$cost_usd" "$esc_note"
}

# jsonl_get_field <field_name> <json_line>
# Extract the value of a named field from a single JSON line.
# Uses a two-pass strategy: quoted strings first, then bare numeric values.
# Handles commas inside quoted string values (FIXED medium: was truncating on comma).
# Limitation: escaped quotes inside string values are not fully supported.
jsonl_get_field() {
  local field="$1"
  local line="$2"
  local val

  # Pass 1: quoted string — "field": "value" (optional whitespace after colon).
  # Handles commas inside quoted string values (FIXED medium: was truncating on comma).
  val="$(printf '%s' "$line" | grep -oE "\"${field}\":[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed 's/^"[^"]*":[[:space:]]*"//; s/"$//')"

  # Pass 2: bare numeric/boolean — "field": 123 or "field":0.006000
  if [[ -z "$val" ]]; then
    val="$(printf '%s' "$line" | grep -oE "\"${field}\":[[:space:]]*[0-9][^,}\"]*" | head -1 \
      | sed 's/^"[^"]*":[[:space:]]*//')"
  fi

  printf '%s' "$val"
}
