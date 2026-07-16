# Tasks: Tolerant Model Matching and Split Fallback Rates

**Input**: Design documents from `specs/003-tolerant-model-matching/`

**Status**: ✅ All complete — implemented retroactively-documented work, shipped in
commit `5095b1e` (v1.3.0, 2026-07-16). No speckit workflow steps were run; this file
records what was actually built for traceability.

## Phase 1: Catalog resolution library

- [X] T001 Rewrite catalog parsing in `scripts/bash/lib/catalog.sh`: `_catalog_rows`
  (awk strips comments/blanks, trims fields) and `_catalog_exact_row` (awk `$1 == id`
  exact-field match, first hit wins) replacing the grep pipeline (FR-008)
- [X] T002 Add `catalog_normalize_model` in `scripts/bash/lib/catalog.sh`: lowercase,
  trim, strip trailing parenthetical, spaces/underscores → dashes, collapse dashes (FR-001)
- [X] T003 Add `catalog_resolve_model` in `scripts/bash/lib/catalog.sh`: 4-rung ladder
  (exact → normalized → dots→dashes → longest dash-boundary prefix) (FR-001)
- [X] T004 Route `catalog_get_rates` through `catalog_resolve_model` (FR-001)

## Phase 2: Recording pipeline

- [X] T005 Use `catalog_resolve_model` in `scripts/bash/record-cost.sh` and store the
  canonical resolved ID in the ledger `model` field (FR-002)
- [X] T006 Add `config_get_price_per_1k_raw` (no default; empty when absent/invalid) in
  `scripts/bash/lib/config.sh` (FR-003)
- [X] T007 Implement split fallback rungs in `scripts/bash/record-cost.sh`: $3/M input,
  $15/M output when no override/catalog/explicit `price_per_1k` applies (FR-003)
- [X] T008 Append inline fallback marker ` (fallback rate — "<model>" not in catalog)`
  to the 💰 summary for named catalog misses; keep spec-001 format for matched/`unknown`
  models; improve the stderr warning text (FR-005)

## Phase 3: Report repricing parity

- [X] T009 Mirror the split-fallback ladder in `resolve_input_rate`/`resolve_output_rate`
  in `scripts/bash/report-cost.sh` (blended rung only when `_cfg_blended` explicitly set) (FR-006)
- [X] T010 Reprice legacy ledger entries stored with display labels via the same
  normalized matching in `scripts/bash/report-cost.sh` (FR-006)

## Phase 4: Configuration & documentation

- [X] T011 Comment out `price_per_1k` in `config-template.yml` (opt-in) and update the
  ladder documentation (FR-004)
- [X] T012 Document the 4 matching rules in the `model-catalog.txt` header (FR-001)
- [X] T013 Update `commands/speckit.cost.record.md` and
  `.github/skills/speckit-cost-record/SKILL.md`: GitHub Copilot display-label guidance
  (Step 3a) and prefer real token counts via `--in-tokens`/`--out-tokens` when the host
  exposes usage (FR-007)
- [X] T014 Bump `extension.yml` to 1.3.0; add `CHANGELOG.md` entry `[1.3.0] - 2026-07-16`;
  gitignore `.specify/extensions/cost/cost-ledger.jsonl`

## Phase 5: Tests & verification

- [X] T015 Add `stub_catalog` helper in `tests/bats/helpers/setup.bash`
- [X] T016 Add 8 "model matching:" cases in `tests/bats/record.bats` (display labels,
  dots, dated variants, longest-prefix disambiguation, marker presence/absence) and
  re-target the SC-002 default test to split fallback ($0.0180 for 1000/1000) (SC-001, SC-003)
- [X] T017 Add 2 SC-003 cases in `tests/bats/report.bats` (split defaults $0.0105;
  display-label reprice $0.0088) and pin the explicit-blended case via `stub_config` (SC-002)
- [X] T018 Run full suite via Git Bash: 17 new/updated cases pass; 5 remaining failures
  confirmed as pre-existing Windows environment artifacts (SC-003)
- [X] T019 End-to-end smoke test against reinstalled dev copy
  (`specify extension add . --dev --force`): `GPT-5.3-Codex` 6000/3000 → $0.0525;
  `claude-opus-4-8-20260220` → $0.0300; unknown → $0.0180 + marker; test ledger entry
  removed via `reset-cost.sh --yes` (SC-001, SC-004)

## Phase 6: Spec alignment (this documentation pass)

- [X] T020 Create `specs/003-tolerant-model-matching/spec.md` with amendments table
- [X] T021 Amend living docs: `specs/002-improve-cost-accuracy/contracts/catalog-format.md`
  (matching ladder), `contracts/config-schema.md` (opt-in `price_per_1k`), `data-model.md`
  (superseded exact-match note), `quickstart.md` Scenario 4 ($0.0045 + marker)
- [X] T022 Add amendment notes to `specs/001-cost-tracking-per-step/spec.md` and
  `specs/002-improve-cost-accuracy/spec.md`; set both Status fields to Implemented
