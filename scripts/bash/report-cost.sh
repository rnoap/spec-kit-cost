#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# report-cost.sh — Read-only per-spec cost breakdown report.
#
# Reads .specify/extensions/cost/cost-ledger.jsonl, filters to the current spec,
# renders a markdown breakdown table, and prints a cumulative USD total.
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

# ── Argument parsing ──────────────────────────────────────────────────────────
spec_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) spec_override="$2"; shift 2 ;;
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
# Use grep to find lines containing the spec field, then awk to filter exactly.
# POSIX-compatible: read matching lines into an array without mapfile (bash 3 safe).
entries=()
while IFS= read -r line; do
  entries+=("$line")
done < <(grep "\"spec\":\"${spec}\"" "$ledger" 2>/dev/null || true)

if [[ ${#entries[@]} -eq 0 ]]; then
  # FR-017, SC-008: explicit empty-state message.
  printf 'No cost data recorded for this spec.\n'
  exit 0
fi

# ── Render breakdown table (CR-P3) ────────────────────────────────────────────
printf '## Cost Report: %s\n\n' "$spec"
printf '| Step | Input tokens | Output tokens | Cost (USD) |\n'
printf '|------|-------------:|-------------:|-----------:|\n'

total_cost="0"

for entry in "${entries[@]}"; do
  step="$(jsonl_get_field step "$entry")"
  display_step="${step#after_}"
  in_tok="$(jsonl_get_field input_tokens "$entry")"
  out_tok="$(jsonl_get_field output_tokens "$entry")"
  cost_raw="$(jsonl_get_field cost_usd "$entry")"

  # Display cost at 4 decimal places.
  cost_4dp="$(awk "BEGIN { printf \"%.4f\", $cost_raw }")"

  printf '| %-12s | %12s | %13s | %10s |\n' \
    "$display_step" "$in_tok" "$out_tok" "\$$cost_4dp"

  # Accumulate total using awk for float precision (R2).
  total_cost="$(awk "BEGIN { printf \"%.6f\", $total_cost + $cost_raw }")"
done

# ── Cumulative total (CR-P4, SC-003) ─────────────────────────────────────────
# Sum from 6dp stored values, displayed at 4dp.
total_4dp="$(awk "BEGIN { printf \"%.4f\", $total_cost }")"
printf '\n**Total: \$%s** (%d step(s))\n' "$total_4dp" "${#entries[@]}"
