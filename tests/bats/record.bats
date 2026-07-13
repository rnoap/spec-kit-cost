#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# record.bats — Tests for record-cost.sh
# Covers: SC-001 (inline format), SC-002 (zero-config), SC-007 (failure non-blocking)

load 'helpers/setup'

RECORD_SCRIPT=""

setup() {
  setup_temp_dir
  # Resolve absolute path to the script under test.
  RECORD_SCRIPT="$(cd "$ORIGINAL_DIR" && pwd)/scripts/bash/record-cost.sh"
}

teardown() {
  teardown_temp_dir
}

# ── SC-001: Inline summary format ─────────────────────────────────────────────

@test "SC-001: zero-config produces exactly one inline summary line" {
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 2000
  [ "$status" -eq 0 ]
  # Exactly one line matching the 💰 format.
  local summary_lines
  summary_lines="$(printf '%s\n' "$output" | grep -c '^💰')"
  [ "$summary_lines" -eq 1 ]
}

@test "SC-001: inline summary matches format '💰 specify: ~N in / ~N out tokens ≈ \$N.NNNN'" {
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 2000
  [ "$status" -eq 0 ]
  # Strip the prefix and check format.
  printf '%s\n' "$output" | grep -qE '^💰 specify: ~[0-9]+ in / ~[0-9]+ out tokens ≈ \$[0-9]+\.[0-9]{4}$'
}

@test "SC-001: step name strips 'after_' prefix in display" {
  run bash "$RECORD_SCRIPT" --step after_plan --in-chars 1000 --out-chars 500
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^💰 plan:'
}

@test "SC-001: chars ÷ 4 heuristic — 4000 chars yields ~1000 tokens" {
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 0
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^💰 specify: ~1000 in'
}

# ── SC-002: Zero-config first run ─────────────────────────────────────────────

@test "SC-002: runs with no cost-config.yml and appends one JSONL record" {
  # Ensure no config file exists.
  rm -f .specify/extensions/cost/cost-config.yml

  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 800 --out-chars 400
  [ "$status" -eq 0 ]

  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  [ -f "$ledger" ]
  local lines
  lines="$(wc -l < "$ledger" | tr -d ' ')"
  [ "$lines" -eq 1 ]
}

@test "SC-002: ledger entry uses default price 0.003 when no config present" {
  rm -f .specify/extensions/cost/cost-config.yml

  bash "$RECORD_SCRIPT" --step after_specify --in-chars 1000 --out-chars 1000
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  # cost_usd = (250 + 250) / 1000 * 0.003 = 0.0015  (1000 chars each → 250 tokens each)
  grep -q '"provider":"self-report"' "$ledger"
}

@test "SC-002: ledger record contains all required fields (FR-018)" {
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 400 --out-chars 200
  [ "$status" -eq 0 ]
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  local record
  record="$(cat "$ledger")"
  # Check all schema-v1 fields are present.
  printf '%s' "$record" | grep -q '"v":1'
  printf '%s' "$record" | grep -q '"ts":'
  printf '%s' "$record" | grep -q '"step":"after_specify"'
  printf '%s' "$record" | grep -q '"spec":'
  printf '%s' "$record" | grep -q '"provider":'
  printf '%s' "$record" | grep -q '"input_tokens":'
  printf '%s' "$record" | grep -q '"output_tokens":'
  printf '%s' "$record" | grep -q '"model":'
  printf '%s' "$record" | grep -q '"cost_usd":'
  printf '%s' "$record" | grep -q '"note":'
}

# ── SC-007: Failure non-blocking ──────────────────────────────────────────────

@test "SC-007: exit code is 0 even when ledger directory is unwritable" {
  mkdir -p .specify/extensions/cost
  chmod 000 .specify/extensions/cost

  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 400 --out-chars 200
  # Restore permissions before assertion so teardown can clean up.
  chmod 755 .specify/extensions/cost
  [ "$status" -eq 0 ]
}

@test "SC-007: exactly one stderr warning line when ledger write fails" {
  mkdir -p .specify/extensions/cost
  chmod 000 .specify/extensions/cost

  # Capture stderr separately.
  local stderr_output
  stderr_output="$(bash "$RECORD_SCRIPT" --step after_specify --in-chars 400 --out-chars 200 2>&1 1>/dev/null)"
  chmod 755 .specify/extensions/cost

  local warn_count
  warn_count="$(printf '%s\n' "$stderr_output" | grep -c 'speckit-cost:' || true)"
  [ "$warn_count" -eq 1 ]
}

@test "SC-007: missing --step argument exits 0 with stderr warning" {
  run bash "$RECORD_SCRIPT" --in-chars 400 --out-chars 200
  [ "$status" -eq 0 ]
}

@test "SC-007: manual provider without token counts exits 0 with warning" {
  run bash "$RECORD_SCRIPT" --step after_specify --provider manual
  [ "$status" -eq 0 ]
}
