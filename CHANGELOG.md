# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-07-14

### Changed
- `AGENTS.md` — added critical warning: this repository is the extension source; AI agents
  must never edit `.specify/extensions/cost/` directly (tool-managed local install).
- `.specify/memory/constitution.md` — added Development Workflow rule 7 prohibiting
  implementation inside the spec-kit local install directory; bumped constitution to 1.1.0.

### Fixed
- Implementation files for spec `002-improve-cost-accuracy` (`catalog.sh`, `model-catalog.txt`,
  updated `config.sh`, `record-cost.sh`, `report-cost.sh`, `commands/speckit.cost.record.md`,
  `config-template.yml`) were previously applied to `.specify/extensions/cost/` instead of the
  repository root. Files migrated to root; `.specify/extensions/cost/` reinstalled from root via
  `specify extension add --dev --force` to restore a clean tool-managed state.

## [1.2.0] - 2026-07-14

### Added
- `model-catalog.txt` — expanded from 17 to 34 entries: added 7 Google Gemini models (`gemini-2.5-pro`, `gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-3-flash-preview`, `gemini-3.1-pro-preview`, `gemini-3.1-flash-lite`, `gemini-3.5-flash`), verified from ai.google.dev/pricing 2026-07-14.
- `model-catalog.txt` — OpenAI additions: `gpt-5.3-codex` (1.75/14), `gpt-5-mini` (0.75/4.5, assumed — not on public API pricing page), `o3-deep-research`, `o4-mini-deep-research`.
- `model-catalog.txt` — Claude additions: `claude-opus-4-7`, `claude-opus-4-5`, `claude-haiku-4-5` short alias, `claude-sonnet-4-5` short alias.

### Changed
- `commands/speckit.cost.record.md` — Step 3a model detection is now **agent-agnostic**: tries 4 signals in order (Wibey/Claude Code harness injection → host agent context → AI self-identification → config fallback). Extension now works correctly with GitHub Copilot, Cursor, and any other AI coding assistant in addition to Wibey.
- `extension.yml` — updated catalog description to reflect multi-provider coverage (Claude + OpenAI + Gemini); removed incorrect "Wibey-only" annotation.

## [1.1.0] - 2026-07-13

### Added
- `model-catalog.txt` — pre-populated model price catalog (pipe-delimited: `model-id|input_per_M_USD|output_per_M_USD`). Ships with 7 Wibey-supported Claude models (rates sourced from wibey-cli `src/constants/models.ts`) and 10 OpenAI models (rates from openai.com/api/pricing, verified 2026-07-13). Updatable by editing one file — no script changes required (FR-007).
- `scripts/bash/lib/catalog.sh` — POSIX catalog lookup library (`catalog_get_rates`, `catalog_get_input_rate`, `catalog_get_output_rate`). Uses only `grep`/`cut`; validates returned rates; emits non-fatal warnings for malformed entries.
- `scripts/bash/lib/config.sh` — two new reader functions: `config_get_input_rate_per_1k` and `config_get_output_rate_per_1k`. Return `""` when absent so callers can detect presence without a default.
- `config-template.yml` — documented new optional keys `input_rate_per_1k` and `output_rate_per_1k` with usage examples, FR-004 priority ladder, and reference to `contracts/config-schema.md`.
- `extension.yml` — declared `model-catalog.txt` under `provides.config`; added `input_rate_per_1k` and `output_rate_per_1k` to `config.defaults` (both `null` by default).
- SDD artifacts for feature `002-improve-cost-accuracy`: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, `tasks.md`, `contracts/catalog-format.md`, `contracts/config-schema.md`.

### Changed
- `record-cost.sh` — now accepts `--model <model-id>` flag; implements FR-004 per-M rate resolution priority ladder (config override → catalog → `price_per_1k` → default); replaces blended `(in+out)×p/1000` formula with two-rate `(in×ir/1M)+(out×or/1M)` formula. Active model stored in ledger `model` field.
- `report-cost.sh` — costs are now **recomputed at display time** from stored token counts + stored model ID using the current catalog/config rates (ignores `cost_usd` stored in ledger); adds **Cumulative** column showing running total through each row; grand total line derives from final cumulative value. Sources `lib/catalog.sh`.
- `commands/speckit.cost.record.md` — added Step 3a: instructs AI to extract the harness-injected model ID from `Current model: <name> (<id>)` in session context and pass it as `--model <id>` to the script. Falls back to `cost-config.yml` `model` key or `unknown`.

### Fixed
- Cost under-reporting for premium models (e.g., Opus 4.8 was billed at Sonnet input rate for all tokens). Output tokens are now priced at their correct, higher rate per model.
- `model` field in ledger entries now reflects the harness-detected model ID rather than the static `cost-config.yml` label.

## [1.0.0] - 2026-07-13

### Added
- `extension.yml` — full extension manifest (3 commands, 7 `after_*` hooks, config block; CR-M1..M5 ✅)
- `config-template.yml` — defaults: `provider: self-report`, `price_per_1k: 0.003`, `model: unknown`
- `scripts/bash/lib/json.sh` — JSONL emit + field extraction; no jq (research R1)
- `scripts/bash/lib/config.sh` — flat YAML key reader with hardcoded defaults (research R3)
- `scripts/bash/record-cost.sh` — per-step cost recording; self-report (`chars÷4`), manual, log-file stub; always exits 0
- `scripts/bash/report-cost.sh` — per-spec breakdown table + cumulative USD total; read-only
- `scripts/bash/reset-cost.sh` — confirmation-gated per-spec ledger reset; atomic temp+mv (research R4)
- `commands/speckit.cost.record.md` — AI hook command with 3-provider branch instructions
- `commands/speckit.cost.report.md` — AI command for on-demand + auto-after-implement report
- `commands/speckit.cost.reset.md` — AI command for safe confirmation-gated reset
- `tests/bats/record.bats` — 9 tests covering SC-001, SC-002, SC-007
- `tests/bats/report.bats` — 8 tests covering SC-003, SC-004, SC-005, SC-008
- `tests/bats/reset.bats` — 7 tests covering SC-006 (a/b/c) + edge cases
- `tests/bats/helpers/setup.bash` — shared bats test scaffolding
- `LICENSE` — MIT, copyright 2026 rnoap
- `.extensionignore` — excludes tests/, specs/, .specify/ from distribution zip
- `README.md` — installation, zero-config quickstart, provider guide, ledger format, dev instructions

### Added (SDD artifacts — `specs/001-cost-tracking-per-step/`)
- Initial spec-kit project setup with `specify init` (integration: claude)
- Project constitution v1.0.0 — five core principles ratified:
  - I. Extension Contract First
  - II. Non-Destructive Tracking (non-negotiable)
  - III. Pluggable Data Source (self-report / log-file / manual)
  - IV. Append-Only Ledger (JSON Lines in `cost-ledger.jsonl`)
  - V. Shell-First, Zero Runtime Dependencies
- `.wibey/skills/` — 19 spec-kit project skills synced and committed
- `specs/` directory scaffolded for spec-driven development
- `AGENTS.md` — Wibey/AI context file with graph-priority section
- `.gitignore` — excludes `.claude/` (machine-local skill copies)
- `git` extension installed (`speckit.git.*` commands)
- `brownfield` extension installed (`speckit.brownfield.*` commands)
- Code knowledge graph built (`.code-review-graph/`)
- Analysis findings resolved across spec.md and tasks.md:
  - FR-012: `manual` provider fully scoped; `log-file` v1.1 stub documented
  - T009/T010: all three provider branches explicitly described
  - T014/SC-005: concrete grep-based manifest wiring assertion
  - T015: §II mktemp transient-write compliance note added
  - Terminology: "spec session" normalized to "spec" throughout spec.md
- `specs/001-cost-tracking-per-step/plan.md` — implementation plan:
  - Extension file structure (`extension.yml`, `commands/`, `scripts/bash/`)
  - Data model: Cost Entry schema v1 (verbatim from constitution §IV)
  - Command ↔ script design table; hook wiring for 7 lifecycle events
  - Supporting artifacts: `research.md`, `data-model.md`, `quickstart.md`, `contracts/`
- `specs/001-cost-tracking-per-step/spec.md` — first feature spec (clarified):
  - 3 user stories (P1 per-step inline summary, P2 cumulative report, P3 safe reset)
  - 18 functional requirements, 8 measurable success criteria, 7 edge cases
  - Key entities: Cost Entry, Cost Ledger, Cost Configuration, Cost Report

---

<!-- CHANGELOG GUIDE
===================
Sections (use only what applies to each release):
  ### Added       — new features
  ### Changed     — changes to existing functionality
  ### Deprecated  — features to be removed in a future release
  ### Removed     — features removed in this release
  ### Fixed       — bug fixes
  ### Security    — security-related fixes

Versioning rules (from constitution Principle I):
  MAJOR — backward-incompatible manifest/hook/command changes
  MINOR — new commands, hooks, or config keys added
  PATCH — bug fixes, doc clarifications, script corrections

Release entry template:
  ## [X.Y.Z] - YYYY-MM-DD
  ### Added
  - ...
  ### Changed
  - ...

Link definitions (update on each release):
  [Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/vX.Y.Z...HEAD
  [X.Y.Z]: https://github.com/rnoap/spec-kit-cost/compare/vA.B.C...vX.Y.Z
-->

[Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.0.0...v1.0.0
