# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-07-16

### Added
- **Cache-aware pricing**: `model-catalog.txt` now supports two optional trailing
  columns — `cache_read_per_M_USD` and `cache_write_per_M_USD` — per
  `model-id|input_per_M_USD|output_per_M_USD[|cache_read_per_M_USD[|cache_write_per_M_USD]]`.
  When absent, cache rates are derived as 0.10× the resolved input rate (cache
  read) and 1.25× the resolved input rate (cache write). `record-cost.sh` and
  `report-cost.sh` both compute cost with a four-term formula —
  `(fresh_in × input + cache_read × cache_read_rate + cache_write × cache_write_rate + output × output) / 1e6`,
  where `fresh_in = max(0, input_tokens − cache_read − cache_write)` — instead of
  pricing the full input total at the input rate.
- `scripts/bash/record-cost.sh` — new `--cache-read-tokens` / `--cache-write-tokens`
  flags (rejected in combination with `--in-chars`/`--out-chars`) and a `--source
  measured|estimated` flag (default `estimated`). An anomaly note is appended when
  cache counts exceed the input total (fresh input is floored at 0).
- **Measured token usage acquisition**: `commands/speckit.cost.record.md` gained a
  new Rung 1 in the `self-report` degradation ladder — on hosts exposing a session-
  store query tool (currently VS Code Copilot), it best-effort reindexes, resolves
  the current session, aggregates real token/cache usage for the active model since
  the last recorded step, and records with `--source measured`. Falls back silently
  to the existing host-usage-panel and chars÷4 rungs on any of five documented
  trigger conditions (no store tool, ambiguous session, unreadable ledger, query
  failure, no matching/zero usage row) — never blocks or alarms the developer.
- Ledger schema gained three additive optional fields: `cache_read_tokens`,
  `cache_write_tokens` (emitted only when > 0), and `source` (emitted only when
  `"measured"`) — legacy entries and invocations remain byte-identical.
- `report-cost.sh` table gained a `Src` column (`m`/`e`) and reprices every entry
  (including legacy ones) with the four-term formula; the Tokens column shows
  `in (N cached)/out` when cache counts are present.
- `tests/bats` — cache-aware pricing tests (explicit catalog rates, derived
  defaults, anomaly flooring, ambiguous-flag rejection, ledger field-emission
  rules), mixed-ledger report tests (Src column, Tokens cell format, cumulative/
  grand totals across measured + estimated entries), and byte-identity regression
  tests proving legacy char-mode/token-mode invocations are unaffected.

### Changed
- `record-cost.sh` inline summary format: gains an optional `(N cached)` segment
  after the input token count and an optional ` [measured]` suffix after the cost,
  composing with the existing fallback-rate suffix. Legacy invocations (no cache
  tokens, no `--source measured`) render byte-identical to v1.3.0.


### Added
- `scripts/bash/lib/catalog.sh` — tolerant model matching ladder (`catalog_resolve_model`):
  exact ID → normalized (case, spaces/underscores → dashes, parentheticals stripped) →
  dots→dashes candidate → longest-prefix match for dated/suffixed variants. UI labels
  like `GPT-5.3-Codex` or `Claude Sonnet 4.6` and variants like
  `claude-sonnet-4-6-20260101` now resolve to their catalog entries instead of
  silently falling back to the blended rate.
- `scripts/bash/record-cost.sh` — visible inline fallback marker: when a *named*
  model misses the catalog, the 💰 summary line now ends with
  `(fallback rate — "<model>" not in catalog)` so degraded accuracy is no longer
  hidden in stderr that agent harnesses may swallow.
- `scripts/bash/lib/config.sh` — `config_get_price_per_1k_raw` (no hardcoded
  default) so scripts can distinguish an explicit legacy blended rate from an
  absent key.
- `tests/bats` — 8 new tests covering case-insensitive/display-label/dated-variant
  matching, canonical ID storage, split fallback amounts, fallback marker, and
  report repricing of legacy display-label entries; new `stub_catalog` helper.
- `.gitignore` — exclude the local cost ledger
  (`.specify/extensions/cost/cost-ledger.jsonl`): workspace-local data, not source.

### Changed
- **Split fallback rates**: when the active model is not in the catalog and no
  explicit `price_per_1k` is configured, cost now uses $3/M input + $15/M output
  (as long documented) instead of a blended $3/M for both — output tokens were
  previously underpriced up to 5×. Setting `price_per_1k` explicitly preserves
  the legacy blended behavior.
- `scripts/bash/record-cost.sh` — the ledger now stores the *canonical* resolved
  catalog ID (e.g. `gpt-5.3-codex`) rather than the raw label passed via `--model`,
  so `report-cost.sh` repricing stays accurate.
- `config-template.yml` — `price_per_1k` is now commented out (opt-in): shipping it
  active pinned every unknown-model estimate to the blended rate.
- `commands/speckit.cost.record.md` + skill copy — Step 3a now covers GitHub
  Copilot display labels (`GPT-5.3-Codex` → `gpt-5.3-codex`) and documents the
  script-side normalization; self-report branch now prefers real token counts via
  `--in-tokens`/`--out-tokens` when the host agent exposes actual usage.
- `AGENTS.md` — expanded project context: repository layout table, development
  workflow (bats, dev-install loop, release checklist), SDD skill map, and
  code-review-graph MCP exploration guidance.

### Fixed
- Model detection failures caused by case/format mismatches (e.g. `GPT-5.3-Codex`
  from the GitHub Copilot UI never matching `gpt-5.3-codex`), which produced
  underestimated fallback-rate entries like $0.0270 instead of $0.0525.
- Doc/code mismatch: config template promised "$3/M input, $15/M output" defaults
  while the code applied blended $3/M to both token types.

## [1.2.2] - 2026-07-14

### Added
- `README.md` — new **AI Assistant Setup** section with the AGENTS.md snippet that
  consuming projects must add to ensure mandatory hooks (`optional: false`) are
  executed by AI agents (GitHub Copilot, Cursor, Wibey) rather than merely listed.

### Changed
- `commands/speckit.cost.record.md` — Step 4 now carries a `(MANDATORY)` marker
  with explicit instruction: relay the 💰 line in response text, not only in
  tool-call logs that developers may not see.
- `commands/speckit.cost.record.md` — self-report branch: added inline warning
  clarifying that `--in-chars`/`--out-chars` accept **character counts** (÷4
  applied by the script) and that passing character counts into `--in-tokens` bypasses
  the heuristic and inflates estimates by ~4×.

### Fixed
- Documented correct flag usage to prevent AI assistants from using `--in-tokens`
  with character counts under the `self-report` provider, which produced
  non-comparable ledger entries across steps.
- `scripts/bash/report-cost.sh` — added `--model <id>` flag for what-if repricing:
  when supplied, overrides the per-entry model used for rate resolution, allowing
  cost recomputation at a different model's rates without modifying ledger data.

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

[Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/v1.2.2...HEAD
[1.2.2]: https://github.com/rnoap/spec-kit-cost/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/rnoap/spec-kit-cost/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/rnoap/spec-kit-cost/compare/v1.0.0...v1.0.0
