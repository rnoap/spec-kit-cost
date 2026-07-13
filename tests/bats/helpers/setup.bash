#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# setup.bash — Shared bats test helpers.
# Source this file in each *.bats test suite's setup() function.

# Create a clean temporary working directory for each test.
setup_temp_dir() {
  export TEST_TMPDIR
  TEST_TMPDIR="$(mktemp -d)"
  export ORIGINAL_DIR="$PWD"
  cd "$TEST_TMPDIR" || exit 1

  # Stub the .specify/feature.json that record-cost.sh reads for spec identity.
  mkdir -p .specify/extensions/cost
  printf '{"feature_directory":"specs/001-cost-tracking-per-step"}\n' \
    > .specify/feature.json

  # Make lib/ scripts discoverable relative to the test working dir.
  # Tests invoke scripts via their absolute path; this sets SCRIPT_ROOT.
  export SCRIPT_ROOT
  SCRIPT_ROOT="$(cd "$ORIGINAL_DIR/../.." 2>/dev/null && pwd || cd "$ORIGINAL_DIR" && pwd)"
}

# Tear down the temporary directory after each test.
teardown_temp_dir() {
  cd "$ORIGINAL_DIR" || true
  rm -rf "$TEST_TMPDIR"
}

# Create a stub cost-config.yml in the ledger directory.
# Usage: stub_config [provider] [price_per_1k] [model]
stub_config() {
  local provider="${1:-self-report}"
  local price="${2:-0.003}"
  local model="${3:-unknown}"
  mkdir -p .specify/extensions/cost
  printf 'provider: %s\nprice_per_1k: %s\nmodel: %s\n' \
    "$provider" "$price" "$model" \
    > .specify/extensions/cost/cost-config.yml
}

# Seed the ledger with N entries for a given spec.
# Usage: seed_ledger_entries <spec_name> <count>
seed_ledger_entries() {
  local spec="$1"
  local count="${2:-1}"
  mkdir -p .specify/extensions/cost
  local ledger=".specify/extensions/cost/cost-ledger.jsonl"
  local steps=("after_specify" "after_clarify" "after_plan" "after_tasks" "after_analyze" "after_checklist" "after_implement")
  for i in $(seq 1 "$count"); do
    local idx=$(( (i - 1) % 7 ))
    local step="${steps[$idx]}"
    printf '{"v":1,"ts":"2026-07-13T12:00:0%sZ","step":"%s","spec":"%s","provider":"self-report","input_tokens":%s,"output_tokens":%s,"model":"unknown","cost_usd":0.00300%s,"note":""}\n' \
      "$i" "$step" "$spec" $((i * 100)) $((i * 50)) "$i" >> "$ledger"
  done
}

# Assert a file contains a pattern (bats-compatible helper).
assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -q "$pattern" "$file" 2>/dev/null; then
    echo "ASSERTION FAILED: '$pattern' not found in '$file'"
    echo "File contents:"
    cat "$file" 2>/dev/null || echo "(file not found)"
    return 1
  fi
}
