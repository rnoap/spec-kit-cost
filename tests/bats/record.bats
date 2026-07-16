#!/usr/bin/env bats
# SPDX-License-Identifier: MIT
# record.bats — Tests for record-cost.sh
# Covers: SC-001 (inline format), SC-002 (zero-config), SC-007 (failure non-blocking)

load 'helpers/setup'

RECORD_SCRIPT=""

setup() {
  setup_temp_dir
  # Resolve script paths using $BATS_TEST_DIRNAME (repo-relative, invocation-independent).
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  RECORD_SCRIPT="$REPO_ROOT/scripts/bash/record-cost.sh"
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

@test "SC-002: no config present uses split fallback rates ($3/M in, $15/M out)" {
  rm -f .specify/extensions/cost/cost-config.yml

  # 4000 chars → 1000 in tokens; 4000 chars → 1000 out tokens.
  # cost = 1000×3/1M + 1000×15/1M = 0.003 + 0.015 = 0.018
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0180'
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
  # FIXED (low): chmod 000 is a no-op for uid 0 — skip under root.
  [ "$(id -u)" -ne 0 ] || skip "chmod test requires non-root user"
  mkdir -p .specify/extensions/cost
  chmod 000 .specify/extensions/cost

  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 400 --out-chars 200
  # Restore permissions before assertion so teardown can clean up.
  chmod 755 .specify/extensions/cost
  [ "$status" -eq 0 ]
}

@test "SC-007: exactly one stderr warning line when ledger write fails" {
  # FIXED (low): chmod 000 is a no-op for uid 0 — skip under root.
  [ "$(id -u)" -ne 0 ] || skip "chmod test requires non-root user"
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

# ── Model matching (FR-002/FR-003): catalog lookup tolerance ───────────────────

@test "model matching: exact catalog ID uses per-model rates" {
  stub_catalog
  # 4000 chars → 1000 in; 4000 chars → 1000 out.
  # gpt-5.3-codex: 1000×1.75/1M + 1000×14/1M = 0.00175 + 0.014 = 0.01575 → $0.0158
  run bash "$RECORD_SCRIPT" --step after_specify --model gpt-5.3-codex \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0158'
  ! printf '%s\n' "$output" | grep -q 'fallback'
}

@test "model matching: display label 'GPT-5.3-Codex' resolves case-insensitively" {
  stub_catalog
  run bash "$RECORD_SCRIPT" --step after_analyze --model 'GPT-5.3-Codex' \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0158'
  ! printf '%s\n' "$output" | grep -q 'fallback'
  # Ledger stores the canonical catalog ID, not the display label.
  grep -q '"model":"gpt-5.3-codex"' .specify/extensions/cost/cost-ledger.jsonl
}

@test "model matching: display name with spaces and dots resolves ('Claude Sonnet 4.6')" {
  stub_catalog
  # claude-sonnet-4-6: 1000×3/1M + 1000×15/1M = 0.018
  run bash "$RECORD_SCRIPT" --step after_plan --model 'Claude Sonnet 4.6' \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0180'
  grep -q '"model":"claude-sonnet-4-6"' .specify/extensions/cost/cost-ledger.jsonl
}

@test "model matching: dated variant resolves to base ID by longest prefix" {
  stub_catalog
  run bash "$RECORD_SCRIPT" --step after_tasks --model claude-sonnet-4-6-20260101 \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0180'
  grep -q '"model":"claude-sonnet-4-6"' .specify/extensions/cost/cost-ledger.jsonl
}

@test "model matching: longest prefix wins (gpt-5.4-mini variant → mini rates)" {
  stub_catalog
  # gpt-5.4-mini: 1000×0.75/1M + 1000×4.5/1M = 0.00525 → $0.0053 (not gpt-5.4's 0.0175)
  run bash "$RECORD_SCRIPT" --step after_tasks --model gpt-5.4-mini-2026-01-01 \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0053'
}

@test "model matching: unrecognized model appends visible fallback marker" {
  stub_catalog
  run bash "$RECORD_SCRIPT" --step after_specify --model totally-new-model \
    --in-chars 4000 --out-chars 4000
  [ "$status" -eq 0 ]
  # Split fallback: 1000×3/1M + 1000×15/1M = 0.018, with inline marker.
  printf '%s\n' "$output" | grep -q '\$0\.0180 (fallback rate — "totally-new-model" not in catalog)'
}

@test "model matching: unknown model produces no fallback marker (SC-001 format intact)" {
  stub_catalog
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 2000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '≈ \$[0-9]+\.[0-9]{4}$'
}

@test "model matching: explicit price_per_1k config preserves legacy blended fallback" {
  stub_config self-report 0.003 unknown
  # blended: (1000 + 500) × 0.003/1K = 0.0045
  run bash "$RECORD_SCRIPT" --step after_specify --in-chars 4000 --out-chars 2000
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '\$0\.0045'
}
