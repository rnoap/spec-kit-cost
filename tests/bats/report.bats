#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# report.bats — Tests for report-cost.sh
# Covers: SC-003 (cumulative sum), SC-004 (spec isolation), SC-005 (manifest wiring), SC-008 (empty state)

load 'helpers/setup'

REPORT_SCRIPT=""
RECORD_SCRIPT=""

setup() {
  setup_temp_dir
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REPORT_SCRIPT="$REPO_ROOT/scripts/bash/report-cost.sh"
  RECORD_SCRIPT="$REPO_ROOT/scripts/bash/record-cost.sh"
}

teardown() {
  teardown_temp_dir
}

# ── SC-003: Cumulative total = sum of per-step costs ─────────────────────────

@test "SC-003: cumulative total equals sum of per-step cost_usd values" {
  # Seed 3 known entries for the current spec manually.
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # Explicit blended config: 3 entries × (1000+500 tokens at $0.003/1K) = $0.0045 each → $0.0135
  stub_config self-report 0.003 unknown
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T10:01:00Z","step":"after_clarify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-13T10:02:00Z","step":"after_plan","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]

  # Total should be 3 × 0.0045 = 0.0135 (displayed at 4dp).
  printf '%s\n' "$output" | grep -q '\*\*Total: \$0\.0135\*\*'
}

@test "SC-003: unknown model without config reprices at split defaults ($3/$15 per M)" {
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # No config file: 1000×3/1M + 500×15/1M = 0.003 + 0.0075 = 0.0105
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.004500,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\*\*Total: \$0\.0105\*\*'
}

@test "SC-003: ledger entry with display-label model reprices via normalized catalog match" {
  mkdir -p .specify/extensions/cost
  stub_catalog
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # Legacy entry recorded with a UI label: gpt-5.3-codex rates apply.
  # 1000×1.75/1M + 500×14/1M = 0.00175 + 0.007 = 0.00875 → $0.0088
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_analyze","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"GPT-5.3-Codex","cost_usd":0.027000,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\*\*Total: \$0\.0088\*\*'
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
  local ext_yml="$REPO_ROOT/extension.yml"
  [ -f "$ext_yml" ]

  # FIXED (low): scope the line-order check to within the after_implement block
  # rather than searching the entire file (avoids false ordering from provides.commands).
  local after_impl_start
  after_impl_start="$(grep -n 'after_implement' "$ext_yml" | head -1 | cut -d: -f1)"
  [ -n "$after_impl_start" ]

  # Extract 10 lines from the after_implement stanza.
  local block
  block="$(tail -n +"$after_impl_start" "$ext_yml" | head -10)"
  printf '%s\n' "$block" | grep -q 'speckit.cost.record'
  printf '%s\n' "$block" | grep -q 'speckit.cost.report'

  # record must appear before report within that block.
  local record_offset report_offset
  record_offset="$(printf '%s\n' "$block" | grep -n 'speckit.cost.record' | head -1 | cut -d: -f1)"
  report_offset="$(printf '%s\n' "$block" | grep -n 'speckit.cost.report' | head -1 | cut -d: -f1)"
  [ "$record_offset" -lt "$report_offset" ]
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

# ── Cache-aware repricing and mixed ledgers (User Story 1, 004-measured-token-usage) ──

@test "US1: Src column shows 'e' for legacy entries and 'm' for measured entries" {
  mkdir -p .specify/extensions/cost
  stub_catalog
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.010500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-16T20:00:00Z","step":"after_plan","spec":"001-cost-tracking-per-step","provider":"self-report","source":"measured","input_tokens":4228197,"output_tokens":49756,"cache_read_tokens":4010305,"model":"claude-sonnet-4-6","cost_usd":2.603108,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^\| specify *\| *e *\|'
  printf '%s\n' "$output" | grep -qE '^\| plan *\| *m *\|'
}

@test "US1: Tokens cell shows '(cached)' for cache-aware rows and 'in/out' for legacy rows" {
  mkdir -p .specify/extensions/cost
  stub_catalog
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.010500,"note":""}\n' >> "$ledger"
  printf '{"v":1,"ts":"2026-07-16T20:00:00Z","step":"after_plan","spec":"001-cost-tracking-per-step","provider":"self-report","source":"measured","input_tokens":4228197,"output_tokens":49756,"cache_read_tokens":4010305,"model":"claude-sonnet-4-6","cost_usd":2.603108,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '1000/500'
  printf '%s\n' "$output" | grep -q '4228197 (4010305 cached)/49756'
}

@test "US1: mixed ledger reprices the legacy row bit-for-bit and sums cumulative/grand total exactly (quickstart Scenario 7)" {
  mkdir -p .specify/extensions/cost
  stub_catalog
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # Pre-feature entry: no cache fields, no source — reprices at split defaults ($3/$15 per M).
  printf '{"v":1,"ts":"2026-07-13T10:00:00Z","step":"after_specify","spec":"001-cost-tracking-per-step","provider":"self-report","input_tokens":1000,"output_tokens":500,"model":"unknown","cost_usd":0.010500,"note":""}\n' >> "$ledger"
  # Cache-aware measured entry: the verified reference session (quickstart Scenario 1).
  printf '{"v":1,"ts":"2026-07-16T20:00:00Z","step":"after_plan","spec":"001-cost-tracking-per-step","provider":"self-report","source":"measured","input_tokens":4228197,"output_tokens":49756,"cache_read_tokens":4010305,"model":"claude-sonnet-4-6","cost_usd":2.603108,"note":""}\n' >> "$ledger"

  run bash "$REPORT_SCRIPT"
  [ "$status" -eq 0 ]
  # Legacy row reprices to its exact v1.3.0 value.
  printf '%s\n' "$output" | grep -q '\$0\.0105'
  # Cache-aware row reprices to the verified reference value.
  printf '%s\n' "$output" | grep -q '\$2\.6031'
  # Grand total is the exact sum across the interleaved entries.
  printf '%s\n' "$output" | grep -q '\*\*Total: \$2\.6136\*\*'
}
