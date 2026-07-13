# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/HEAD...HEAD
