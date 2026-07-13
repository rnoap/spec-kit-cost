#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# reset-cost.sh — Confirmation-gated per-spec ledger reset.
#
# Without --yes: prints confirmation instructions and exits 0 (no data modified).
# With --yes:    rewrites the ledger removing only the current spec's entries.
#               Uses temp file + atomic mv for safety (R4).
#
# §II + atomic mv note (FIXED low): mktemp is created beside the ledger
# (same filesystem) to guarantee a true atomic rename rather than a cross-
# filesystem copy+unlink. The durable write target remains cost-ledger.jsonl.
#
# Usage:
#   reset-cost.sh [--spec <feature-dir-name>] [--yes]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/json.sh
source "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
spec_override=""
confirmed=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --spec) spec_override="$2"; shift 2 ;;
    --yes)  confirmed=1; shift ;;
    *) shift ;;
  esac
done

# ── Resolve spec identifier (FR-004) ─────────────────────────────────────────
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

# ── Guard: require --yes (CR-X1, FR-009, SC-006) ─────────────────────────────
if [[ "$confirmed" -eq 0 ]]; then
  printf 'Confirmation required — pass --yes to clear cost entries for "%s".\n' "$spec"
  printf 'This action removes all recorded cost entries for this spec from the ledger.\n'
  printf 'Entries for other specs are not affected.\n'
  exit 0
fi

# ── Locate ledger ─────────────────────────────────────────────────────────────
ledger="$(config_get_ledger_path)"

if [[ ! -f "$ledger" ]]; then
  printf 'speckit-cost: ledger not found at "%s" — nothing to reset.\n' "$ledger"
  exit 0
fi

# ── Atomic rewrite (CR-X2, R4, §II) ──────────────────────────────────────────
# FIXED (low): create temp file beside the ledger (same filesystem) to ensure
# atomic rename rather than cross-filesystem copy+unlink (R4 research decision).
# FIXED (medium): use -F (fixed-string) to prevent BRE metachar data loss.
tmp="$(mktemp "${ledger}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

# Write all lines that do NOT belong to the current spec into the temp file.
grep -vF "\"spec\":\"${spec}\"" "$ledger" > "$tmp" 2>/dev/null || true

# Count removed entries.
original_count="$(wc -l < "$ledger" | tr -d ' ')"
new_count="$(wc -l < "$tmp" | tr -d ' ')"
removed=$(( original_count - new_count ))

# Atomically replace the ledger with the filtered temp file (CR-X4).
mv "$tmp" "$ledger"

# Trap no longer needs to remove $tmp since mv succeeded.
trap - EXIT

printf 'speckit-cost: removed %d entr%s for spec "%s".\n' \
  "$removed" "$([ "$removed" -eq 1 ] && echo 'y' || echo 'ies')" "$spec"

if [[ "$new_count" -eq 0 ]]; then
  printf 'Ledger is now empty.\n'
else
  printf '%d entr%s for other specs preserved.\n' \
    "$new_count" "$([ "$new_count" -eq 1 ] && echo 'y' || echo 'ies')"
fi
