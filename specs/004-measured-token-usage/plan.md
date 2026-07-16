# Implementation Plan: Measured Token Usage and Cache-Aware Cost Pricing

**Branch**: `004-measured-token-usage` | **Date**: 2026-07-16 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/004-measured-token-usage/spec.md`

## Summary

Replace the chars÷4 estimation with exact, host-reported token usage wherever the host
assistant exposes per-call usage records (first host: VS Code Copilot's session store),
and make the pricing engine cache-aware so exact counts produce exact costs. Two layers:

1. **Pricing engine (scripts + catalog)** — the catalog gains optional per-model
   cache-read/cache-write rates; `record-cost.sh` accepts cache token counts and prices
   four independent terms (fresh input, cache read, cache write, output);
   `report-cost.sh` reprices with the same terms. Entries without cache counts behave
   bit-for-bit as today.
2. **Acquisition (agent/skill level only)** — `commands/speckit.cost.record.md` gains a
   preferred "measured" branch: the AI agent queries the host's session store, sums
   per-call usage scoped to the current session + active model + step window, and passes
   explicit counts via flags. Scripts never query any store (Constitution §V). On hosts
   without usage records the flow is byte-identical to v1.3.0.

Verified motivating case: a real session recorded 4.23M input tokens of which 4.01M were
cache reads — naive full-rate pricing puts the input side at ≈ $12.68 vs ≈ $1.86
cache-aware (6.8×); the full entry: ≈ $13.43 naive vs ≈ $2.60 correct (research D9).

## Technical Context

**Language/Version**: Bash (POSIX-compatible; no bash 5.x-only features, per Constitution §V)

**Primary Dependencies**: None at runtime (awk, grep, sed, cut, date — standard POSIX
utilities). Agent-level acquisition uses the host's own session-store tool (VS Code
Copilot: DuckDB-dialect SQL via the built-in session store tool) — never invoked from
shell scripts.

**Storage**: `.specify/extensions/cost/cost-ledger.jsonl` (append-only JSON Lines,
schema v1 + additive optional fields); `model-catalog.txt` (pipe-delimited, 3→5 fields,
backward compatible)

**Testing**: bats-core (`tests/bats/`), run via Git Bash on Windows / native bash on
Unix. Known pre-existing Windows failures (4× SC-001 emoji locale, 1× SC-007 chmod)
are not regressions and stay out of scope.

**Target Platform**: Any AI coding assistant host (Wibey, GitHub Copilot, Cursor,
Claude Code); shell scripts run on Linux/macOS/Windows-Git-Bash

**Project Type**: spec-kit extension (CLI scripts + AI command prompts)

**Performance Goals**: Hook completes in interactive time (<2s script execution);
agent-side store query adds at most one reindex + two SQL calls per step

**Constraints**: Non-blocking (always exit 0 from hooks, FR-013/SC-006); writes
restricted to `.specify/extensions/cost/` (§II); append-only ledger (§IV); zero new
runtime dependencies (§V, FR-014)

**Scale/Scope**: 7 lifecycle steps per spec; ledgers of tens-to-hundreds of lines;
catalog of ~30 models

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Extension Contract First | ✅ PASS | No new commands or hooks; `extension.yml` already bumped to 1.4.0 on this branch. New CLI flags are script-internal, not manifest surface. Manifest description unchanged. |
| II | Non-Destructive Tracking | ✅ PASS | All writes remain inside `.specify/extensions/cost/`. The measured branch only *reads* the host session store. |
| III | Pluggable Data Source | ✅ PASS | No provider added/removed. Measured usage is a preferred **data source inside `self-report`** (falls back to chars÷4), keeping the provider enum stable. Documented in contracts. |
| IV | Append-Only Ledger | ✅ PASS | Additive optional fields (`cache_read_tokens`, `cache_write_tokens`, `source`); absent = zero/estimated. Existing field semantics unchanged → schema stays `"v": 1`. No mutation of existing lines. |
| V | Shell-First, Zero Runtime Dependencies | ✅ PASS | Store queries happen exclusively at agent level (FR-014). Scripts gain only awk arithmetic. No jq/DuckDB/Python from bash. |
| — | Workflow rule 7 (source of truth) | ✅ PASS | All edits at repo root; `.specify/extensions/cost/` regenerated via `specify extension add . --dev --force` (currently uninstalled locally — reinstall optional). |

**Post-Phase-1 re-check (2026-07-16)**: design artifacts introduce no violations —
same verdicts as above. Complexity Tracking not needed.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
commands/
└── speckit.cost.record.md   # + Step 3 measured-usage branch (acquisition contract)

scripts/bash/
├── record-cost.sh           # + --cache-read-tokens/--cache-write-tokens/--source,
│                            #   4-term pricing, cache-aware summary line
├── report-cost.sh           # + cache-aware repricing, Source column/marker
└── lib/
    ├── catalog.sh           # + optional fields 4–5 parsing, cache-rate getters,
    │                        #   derivation defaults (0.10× / 1.25× input rate)
    ├── config.sh            # unchanged (no new config keys — research D8)
    └── json.sh              # + optional cache/source fields in jsonl_emit

model-catalog.txt            # 5-field rows for models with published cache rates
                             # + claude-fable-5 entry (gap found while dogfooding)

tests/bats/
├── record.bats              # + cache math, separation/floor, source, back-compat
├── report.bats              # + mixed-ledger repricing, cache disclosure
└── helpers/setup.bash       # (touch only if fixtures need 5-field catalog samples)

CHANGELOG.md                 # 1.4.0 entry
README.md                    # measured mode + cache pricing docs
```

**Structure Decision**: Existing single-project layout is retained unchanged — this
feature only extends files already present at the repository root. No new directories.

## Complexity Tracking

*No Constitution Check violations — table intentionally empty.*
