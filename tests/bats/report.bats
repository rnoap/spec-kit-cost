#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# report.bats — Tests for report-cost.sh
# Covers: SC-003 (cumulative sum), SC-004 (spec isolation), SC-005 (manifest wiring), SC-008 (empty state)

load 'helpers/setup'

REPORT_SCRIPT=""
RECORD_SCRIPT=""

setup() {
  setup_temp_dir
  REPORT_SCRIPT="$(cd "$ORIGINAL_DIR" && pwd)/scripts/bash/report-cost.sh"
  RECORD_SCRIPT="$(cd "$ORIGINAL_DIR" && pwd)/scripts/bash/record-cost.sh"
}

teardown() {
  teardown_temp_dir
}

# ── SC-003: Cumulative total = sum of per-step costs ─────────────────────────

@test "SC-003: cumulative total equals sum of per-step cost_usd values" {
  # Seed 3 known entries for the current spec manually.
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # 3 entries: 1000+500 tokens each at $0.003/1K = $0.0045 each → total $0.0135
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T10:01:00Z","step":"after_clarify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T10:02:00Z","step":"after_plan","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]

  # Total should be 3 × 0.0045 = 0.0135 (displayed at 4dp).
  printf '%s\n' "$output" | grep -q '\*\*Total: \$0\.0135\*\*'
}

@test "SC-003: table has one row per ledger entry for current spec" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  seed_ledger_entries "001-cost-tracking-per-step" 3

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]

  # Count data rows (lines starting with | but not the header or separator).
  local data_rows
  data_rows="$(printf '%s\n' "$output" | grep -cE '^\| (specify|clarify|plan|tasks|analyze|checklist|implement)' || true)"
  [ "$data_rows" -eq 3 ]
}

# ── SC-004: Spec isolation ────────────────────────────────────────────────────

@test "SC-004: report includes only entries for the current spec" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # One entry for a different spec.
  printf '{"v":1,"ts":"2026-07-13T09:00:00Z","step":"after_specify","spec":"002-other-feature","provider":"self-report","input_tokens":9999,"output_tokens":9999,"model":"unknown","cost_usd":99.999000,"note":""}\n' >> "$ledger"
  # One entry for the current spec.
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":100,"output_tokens":50,"model":"unknown","cost_usd":0.000450,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]

  # The report must not include 9999 tokens from the other spec.
  ! printf '%s\n' "$output" | grep -q '9999'
  # The report must include the current spec's entry.
  printf '%s\n' "$output" | grep -q '001-cost-tracking-per-step'
}

@test "SC-004: --spec override filters to the specified spec only" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  printf '{"v":1,"ts":"2026-07-13T09:00:00Z","step":"after_specify","spec":"002-other-feature","provider":"self-report","input_tokens":500,"output_tokens":250,"model":"unknown","cost_usd":0.002250,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":100,"output_tokens":50,"model":"unknown","cost_usd":0.000450,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT" --spec "002-other-feature"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '002-other-feature'
  ! printf '%s\n' "$output" | grep -q '001-cost-tracking-per-step'
}

# ── SC-005: after_implement hook wiring (manifest contract check) ─────────────

@test "SC-005: extension.yml after_implement block chains speckit.cost.record then speckit.cost.report" {
  local ext_yml="$(cd "$ORIGINAL_DIR" && pwd)/extension.yml"
  [ -f "$ext_yml" ]

  # Extract the after_implement block and assert both commands appear in order.
  local block
  block="$(grep -A10 'after_implement' "$ext_yml")"
  printf '%s\n' "$block" | grep -q 'speckit.cost.record'
  printf '%s\n' "$block" | grep -q 'speckit.cost.report'

  # record must appear before report.
  local record_line report_line
  record_line="$(grep -n 'speckit.cost.record' "$ext_yml" | tail -1 | cut -d: -f1)"
  report_line="$(grep -n 'speckit.cost.report' "$ext_yml" | tail -1 | cut -d: -f1)"
  [ "$record_line" -lt "$report_line" ]
}

# ── SC-008: Empty state ───────────────────────────────────────────────────────

@test "SC-008: empty ledger produces explicit empty-state message" {
  # No ledger file at all.
  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'No cost data recorded for this spec'
}

@test "SC-008: ledger exists but has no entries for current spec → empty-state message" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  printf '{"v":1,"ts":"2026-07-13T09:00:00Z","step":"after_specify","spec":"999-different","provider":"self-report","input_tokens":100,"output_tokens":50,"model":"unknown","cost_usd":0.000450,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'No cost data recorded for this spec'
}
