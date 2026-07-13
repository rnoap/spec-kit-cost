#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# reset.bats — Tests for reset-cost.sh
# Covers: SC-006 (confirmation required, decline preserves ledger, confirm clears spec entries)

load 'helpers/setup'

RESET_SCRIPT=""
REPORT_SCRIPT=""

setup() {
  setup_temp_dir
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RESET_SCRIPT="$REPO_ROOT/scripts/bash/reset-cost.sh"
  REPORT_SCRIPT="$REPO_ROOT/scripts/bash/report-cost.sh"
}

teardown() {
  teardown_temp_dir
}

# ── SC-006a: Confirmation required ───────────────────────────────────────────

@test "SC-006a: without --yes, exits 0 and prints confirmation instructions" {
  seed_ledger_entries "001-cost-tracking-per-step" 2
  run bash "$RESET_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qi 'confirmation required'
}

@test "SC-006a: without --yes, ledger is byte-for-byte unchanged" {
  seed_ledger_entries "001-cost-tracking-per-step" 2
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  local before
  before="$(cat "$ledger")"

  bash "$RESET_SCRIPT" > /dev/null 2>&1

  local after
  after="$(cat "$ledger")"
  [ "$before" = "$after" ]
}

# ── SC-006b: Confirmed reset removes only current spec's entries ──────────────

@test "SC-006b: --yes removes all entries for the current spec" {
  seed_ledger_entries "001-cost-tracking-per-step" 3
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"

  run bash "$RESET_SCRIPT" --yes
  [ "$status" -eq 0 ]

  # No remaining lines with the current spec.
  ! grep -q '"spec":"001-cost-tracking-per-step"' "$ledger" 2>/dev/null
}

@test "SC-006b: --yes preserves entries for other specs" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # Two entries for current spec.
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":100,"output_tokens":50,"model":"unknown","cost_usd":0.000450,"note":""}\n' >> "$ledger"
  # One entry for a different spec.
  printf '{"v":1,"ts":"2026-07-13T09:00:00Z","step":"after_specify","spec":"002-other-feature","provider":"self-report","input_tokens":200,"output_tokens":100,"model":"unknown","cost_usd":0.000900,"note":""}\n' >> "$ledger"

  bash "$RESET_SCRIPT" --yes

  # The other spec's entry must still be present.
  grep -q '"spec":"002-other-feature"' "$ledger"
  # The current spec's entry must be gone.
  ! grep -q '"spec":"001-cost-tracking-per-step"' "$ledger"
}

@test "SC-006b: reports number of removed entries" {
  seed_ledger_entries "001-cost-tracking-per-step" 3
  run bash "$RESET_SCRIPT" --yes
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'removed [0-9]+ entr'
}

# ── SC-006c: After reset, report shows empty-state message ───────────────────

@test "SC-006c: after confirmed reset, report shows empty-state message" {
  seed_ledger_entries "001-cost-tracking-per-step" 2
  bash "$RESET_SCRIPT" --yes > /dev/null 2>&1

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'No cost data recorded for this spec'
}

# ── Edge cases ────────────────────────────────────────────────────────────────

@test "reset with --yes when ledger does not exist exits 0" {
  run bash "$RESET_SCRIPT" --yes
  [ "$status" -eq 0 ]
}

@test "reset with --spec override removes only the specified spec's entries" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":100,"output_tokens":50,"model":"unknown","cost_usd":0.000450,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T09:00:00Z","step":"after_specify","spec":"002-other-feature","provider":"self-report","input_tokens":200,"output_tokens":100,"model":"unknown","cost_usd":0.000900,"note":""}\n' >> "$ledger"

  bash "$RESET_SCRIPT" --spec "002-other-feature" --yes

  grep -q '"spec":"001-cost-tracking-per-step"' "$ledger"
  ! grep -q '"spec":"002-other-feature"' "$ledger"
}
