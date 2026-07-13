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
jsonl_emit() {
  local step="" spec="" provider="" input_tokens="" output_tokens=""
  local model="unknown" cost_usd="" note=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --step)         step="$2";          shift 2 ;;
      --spec)         spec="$2";          shift 2 ;;
      --provider)     provider="$2";      shift 2 ;;
      --input_tokens) input_tokens="$2";  shift 2 ;;
      --output_tokens)output_tokens="$2"; shift 2 ;;
      --model)        model="$2";         shift 2 ;;
      --cost_usd)     cost_usd="$2";      shift 2 ;;
      --note)         note="$2";          shift 2 ;;
      *) shift ;;
    esac
  done

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Escape free-text fields.
  local esc_spec esc_model esc_note
  esc_spec="$(json_escape "$spec")"
  esc_model="$(json_escape "$model")"
  esc_note="$(json_escape "$note")"

  printf '{"v":1,"ts":"%s","step":"%s","spec":"%s","provider":"%s","input_tokens":%s,"output_tokens":%s,"model":"%s","cost_usd":%s,"note":"%s"}\n' \
    "$ts" "$step" "$esc_spec" "$provider" "$input_tokens" "$output_tokens" \
    "$esc_model" "$cost_usd" "$esc_note"
}

# jsonl_get_field <field_name> <json_line>
# Extract the value of a named field from a single JSON line.
# Handles string and numeric values. No jq required.
# Returns the raw value (unquoted for strings, as-is for numbers).
jsonl_get_field() {
  local field="$1"
  local line="$2"
  # Match "field":"value" (string) or "field":value (number/bool).
  printf '%s' "$line" | \
    grep -o "\"${field}\":[^,}]*" | \
    head -1 | \
    sed 's/^"[^"]*"://; s/^"//; s/"$//'
}
