# Tasks: Accurate Model-Aware Cost Calculation and Cumulative Report Table

**Input**: Design documents from `specs/002-improve-cost-accuracy/`

**Prerequisites**: plan.md ✅ · spec.md ✅ · research.md ✅ · data-model.md ✅ · contracts/ ✅ · quickstart.md ✅

**Tests**: Not requested. Validation scenarios in `quickstart.md` are used instead.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: User story this task belongs to (US1 · US2 · US3)
- Exact file paths included in all descriptions

---

## Phase 1: Setup — New Shared Infrastructure

**Purpose**: Create the two new files (catalog + library) that all three user stories depend on. No existing files are modified in this phase.

- [x] T001 Create `.specify/extensions/cost/model-catalog.txt` with all entries from `specs/002-improve-cost-accuracy/research.md` § Catalog Data Sources — Claude models (7 entries, rates from wibey-cli `src/constants/models.ts`) and OpenAI models (10 entries, rates from openai.com/api/pricing verified 2026-07-13). Include comment header documenting pipe-delimiter format, rate unit (USD per million tokens), and source references per `specs/002-improve-cost-accuracy/contracts/catalog-format.md`.

- [x] T002 [P] Create `.specify/extensions/cost/scripts/bash/lib/catalog.sh` — implement `catalog_get_rates <model_id>` (returns `input_per_M|output_per_M` or `""`), `catalog_get_input_rate <model_id>`, and `catalog_get_output_rate <model_id>` using only `grep -v '^[[:space:]]*#'` + `grep -m 1 "^${model_id}|"` + `cut -d'|'` — no external tools. Default `CATALOG_FILE=".specify/extensions/cost/model-catalog.txt"`. Validate returned rates are numeric (`[0-9]+(\.[0-9]+)?`); emit warning to stderr and return `""` on bad data. Add MIT SPDX header matching existing lib files.

---

## Phase 2: Foundational — Rate Resolution Prerequisites

**Purpose**: Extend `lib/config.sh` with readers for the two new config keys. Blocks nothing on its own but gates the rate-resolution logic in Phases 3 and 5.

**⚠️ CRITICAL**: Complete before implementing rate resolution in `record-cost.sh` or `report-cost.sh`

- [x] T003 Modify `.specify/extensions/cost/scripts/bash/lib/config.sh` — add `config_get_input_rate_per_1k` and `config_get_output_rate_per_1k` functions that follow the identical `grep`/`sed` pattern of the existing `config_get` function (no default fallback — return `""` when key absent so callers can detect absence). Do NOT change `config_get`, `config_get_ledger_dir`, or `config_get_ledger_path`.

**Checkpoint**: Foundation ready — user story implementation can now begin

---

## Phase 3: User Story 1 — Zero-Config Accurate Cost via Model Catalog (Priority: P1) 🎯 MVP

**Goal**: A developer using any Wibey-supported model gets an accurate cost at the end of each step with no configuration required. The model is detected from harness context; catalog prices are applied automatically.

**Independent Test**: Run Scenario 1 (Sonnet) and Scenario 2 (Opus) from `specs/002-improve-cost-accuracy/quickstart.md`. Verify costs match expected per-M formula values to 4dp without any `cost-config.yml` changes.

- [x] T004 [US1] Modify `.specify/extensions/cost/scripts/bash/record-cost.sh` — add `model_override=""` variable and `--model) model_override="$2"; shift 2 ;;` to the existing argument-parsing `while` loop (same pattern as `--provider` flag). After arg parsing, set `active_model="${model_override:-$(config_get model)}"` with fallback to `"unknown"`.

- [x] T005 [P] [US1] Add `source "${SCRIPT_DIR}/lib/catalog.sh"` to `.specify/extensions/cost/scripts/bash/record-cost.sh` directly below the existing `source "${SCRIPT_DIR}/lib/config.sh"` line so catalog functions are available.

- [x] T006 [US1] Implement FR-004 rate resolution block in `.specify/extensions/cost/scripts/bash/record-cost.sh` — after `active_model` is set, (1) read `cfg_input_rate=$(config_get_input_rate_per_1k)` and `cfg_output_rate=$(config_get_output_rate_per_1k)` and `cfg_blended=$(config_get price_per_1k)` (default `"0.003"` if blank); (2) call `catalog_get_rates "$active_model"` and split into `catalog_in`/`catalog_out` via `cut`; emit warning to stderr if model not in catalog and not `"unknown"`; (3) resolve `input_rate_M` (per-M, normalized ×1000 from per-1K config): config key → catalog → blended; (4) resolve `output_rate_M` same order; (5) replace the existing `cost_usd` awk formula with `(i * ir / 1000000) + (o * or_ / 1000000)` using awk `-v` flags for `ir` and `or_`. Pass `active_model` to `jsonl_emit` via `--model` flag.

- [x] T007 [US1] Update `.specify/extensions/cost/commands/speckit.cost.record.md` — insert **Step 3a — Detect active model** before the existing Step 3 provider branch: instruct the AI to find the "Current model: \<display-name\> (\<model-id\>)" line in its session context (injected by the Wibey harness), extract the model ID from the parenthetical (e.g., `claude-sonnet-4-6`), and append `--model <model-id>` to every `bash scripts/bash/record-cost.sh` invocation in the file. If no such line is found, fall back to the `model` value from `cost-config.yml`, or `unknown`.

- [x] T008 [P] [US1] Update `.specify/extensions/cost/extension.yml` — under `provides.config` add entry `{ name: "model-catalog.txt", description: "Pre-populated model price catalog (model-id|input_per_M_USD|output_per_M_USD)", required: false }`; under `config.defaults` add `input_rate_per_1k: null` and `output_rate_per_1k: null`.

**Checkpoint**: With T001–T008 complete, a workflow step using any catalog-listed model produces a cost that matches `(in × input_rate_M / 1e6) + (out × output_rate_M / 1e6)` to 4dp with zero config changes.

---

## Phase 4: User Story 2 — Manual Rate Override (Priority: P2)

**Goal**: A developer with a custom enterprise rate or an unlisted model can set `input_rate_per_1k` and/or `output_rate_per_1k` in `cost-config.yml` and have those values take priority over the catalog.

**Independent Test**: Set `input_rate_per_1k: 0.010` in `cost-config.yml`, run Scenario 3 from `specs/002-improve-cost-accuracy/quickstart.md` with `--model claude-sonnet-4-6`, verify cost = `(1000×10/1e6) + (500×15/1e6) = $0.0175` (input from config, output from catalog).

*Note*: The rate resolution logic that enables this story was implemented in T006 (Phase 3). T009 below completes the user-facing documentation that makes the feature discoverable.

- [x] T009 [US2] Update `.specify/extensions/cost/config-template.yml` — after the existing `price_per_1k` block add a commented block documenting `input_rate_per_1k` and `output_rate_per_1k` with: purpose (per-type override, takes priority over catalog for that token type), unit (USD per 1,000 tokens), example values, note that partial config (only one key set) applies that key's rate while the other resolves from the catalog, and reference to `specs/002-improve-cost-accuracy/contracts/config-schema.md` for the full priority ladder.

**Checkpoint**: With T009 complete, developers can discover and apply manual rate overrides via config comments alone, with no script knowledge required.

---

## Phase 5: User Story 3 — Cumulative Running Total in Report Table (Priority: P3)

**Goal**: The cost report table gains a "Cumulative" column showing the running total through each row. Costs are recomputed at display time from stored token counts + stored model ID, so correcting the catalog or config immediately reflects in the report.

**Independent Test**: Run Scenario 5 from `specs/002-improve-cost-accuracy/quickstart.md` (requires at least two ledger entries). Verify: (a) "Cumulative" column present; (b) last row's Cumulative = grand total; (c) Cost (USD) values differ from what was stored in `cost_usd` when catalog prices have been corrected since record time.

- [x] T010 [US3] Add `source "${SCRIPT_DIR}/lib/catalog.sh"` to `.specify/extensions/cost/scripts/bash/report-cost.sh` directly below the existing `source "${SCRIPT_DIR}/lib/config.sh"` line.

- [x] T011 [US3] Add `resolve_input_rate` and `resolve_output_rate` inline functions to `.specify/extensions/cost/scripts/bash/report-cost.sh` — same FR-004 priority ladder as T006 (`config_get_input_rate_per_1k` → catalog → `price_per_1k` → default 3/15 per-M), reading config keys once before the entry loop and passing `model_id` argument to `catalog_get_rates` per entry. **Unit normalization required**: config values are per-1K and MUST be multiplied ×1000 to produce per-M before use in the cost formula — see `data-model.md` § Rate Resolution State and T006 implementation for the identical conversion. Omitting this step produces costs 1000× too low when a config override is active.

- [x] T012 [US3] Modify the entry loop in `.specify/extensions/cost/scripts/bash/report-cost.sh` — add `entry_model="$(jsonl_get_field model "$entry")"` extraction immediately after `out_tok` extraction; default to `"unknown"` if blank.

- [x] T013 [US3] Replace `cost_raw="$(jsonl_get_field cost_usd "$entry")"` in `.specify/extensions/cost/scripts/bash/report-cost.sh` with recomputed cost: call `resolve_input_rate "$entry_model"` and `resolve_output_rate "$entry_model"`, then compute `cost_raw` via `awk -v i="$in_tok" -v o="$out_tok" -v ir="$input_rate_M" -v or_="$output_rate_M" 'BEGIN { printf "%.6f", (i * ir / 1000000) + (o * or_ / 1000000) }'`. Remove the now-unused `cost_raw` validation block (the `[0-9]+(\.[0-9]+)?` guard was for ledger-read floats — computed values are always valid).

- [x] T014 [US3] Add cumulative column to `.specify/extensions/cost/scripts/bash/report-cost.sh` — (1) initialize `cumulative="0"` before the entry loop; (2) after computing `cost_raw`, accumulate: `cumulative="$(awk -v t="$cumulative" -v c="$cost_raw" 'BEGIN { printf "%.6f", t + c }')"` and format `cumulative_4dp="$(awk -v c="$cumulative" 'BEGIN { printf "%.4f", c }')"`.

- [x] T015 [US3] Update the report table formatting in `.specify/extensions/cost/scripts/bash/report-cost.sh` — (1) change header `printf` to include `| Cumulative |` as 5th column; (2) add `|---------------------------:|` to separator; (3) append `"\$$cumulative_4dp"` as the 5th field in the row `printf`; (4) update the grand total line to `printf '\n**Total: $%s** (%d step(s))\n' "$cumulative_4dp" "${#entries[@]}"` (derives from final cumulative, not separate sum).

**Checkpoint**: With T010–T015 complete, the report table shows a Cumulative column, grand total matches final row, and all costs are recomputed from token counts + catalog rates rather than stored `cost_usd`.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: End-to-end validation, documentation consistency, and minor housekeeping.

- [x] T016 [P] Run all 6 validation scenarios from `specs/002-improve-cost-accuracy/quickstart.md` against the updated scripts. Confirm each scenario produces the exact expected output documented in the quickstart. Fix any discrepancies in the scripts (not in the quickstart).

- [x] T017 Verify model detection end-to-end: inspect a ledger entry written after a real `after_specify` hook fires and confirm the `model` field contains a harness-detected model ID (e.g., `claude-sonnet-4-6`) rather than `"unknown"` or the old static config value.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately; T001 and T002 are parallel
- **Phase 2 (Foundational)**: No strict dependency on Phase 1, but complete before Phases 3 and 5
- **Phase 3 (US1)**: Requires Phase 1 (T001 + T002) and Phase 2 (T003) — T004, T005, T007, T008 parallelizable; T006 depends on T004 and T005
- **Phase 4 (US2)**: Requires Phase 3 complete (rate resolution must exist to verify override behavior)
- **Phase 5 (US3)**: Requires Phase 1 (T002 — catalog.sh) and Phase 2 (T003) — T010, T011 parallelizable; T012 → T013 → T014 → T015 sequential within report-cost.sh
- **Phase 6 (Polish)**: Requires all Phases complete

### User Story Dependencies

- **US1 (P1)**: Requires Phases 1 + 2 complete. No dependency on US2 or US3.
- **US2 (P2)**: Requires US1 complete (rate resolution code built in T006). Adds documentation only.
- **US3 (P3)**: Requires Phase 1 (T002) and Phase 2 (T003). Independent of US1 implementation in `record-cost.sh`.

### Within Phase 3 (US1)

```
T001 ──┐
T002 ──┤─→ T005 ──┐
T003 ──┘           ├─→ T006
                  T004 ──┘
T007 ─── (parallel, same file as T006 but different section)
T008 ─── (parallel, different file)
```

### Within Phase 5 (US3)

```
T001/T002 → T010 → T011 ─────┐
T003 ──────────────────────────┤
                               ├→ T012 → T013 → T014 → T015
```

---

## Parallel Opportunities

### Phase 1

```bash
# Both can run simultaneously (different new files):
Task: "T001 Create model-catalog.txt"
Task: "T002 Create lib/catalog.sh"
```

### Phase 3 (US1)

```bash
# Start together after Phase 1+2 complete:
Task: "T004 Add --model arg parsing to record-cost.sh"
Task: "T005 Source catalog.sh in record-cost.sh"
Task: "T007 Update speckit.cost.record.md"
Task: "T008 Update extension.yml"
# Then:
Task: "T006 Implement rate resolution (depends on T004 + T005)"
```

### Phase 5 (US3)

```bash
# Start together (US3 is independent of US1 implementation):
Task: "T010 Source catalog.sh in report-cost.sh"
Task: "T011 Add resolve functions to report-cost.sh"
# Then sequentially in report-cost.sh:
Task: "T012 → T013 → T014 → T015"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001, T002)
2. Complete Phase 2: Foundational (T003)
3. Complete Phase 3: User Story 1 (T004–T008)
4. **STOP and VALIDATE**: Run Scenarios 1 and 2 from quickstart.md
5. MVP delivered: accurate zero-config cost for all Wibey-supported models

### Incremental Delivery

1. **MVP** (Phase 1–3): Accurate catalog pricing, auto-detected model — highest-impact fix
2. **+US2** (Phase 4): Config documentation — makes manual overrides discoverable
3. **+US3** (Phase 5–6): Cumulative report column + recomputation — readability improvement

### Single-Developer Sequence

```
T001 → T002 (parallel) → T003 → T004 → T005 → T006 → T007 → T008
→ [US1 validation: Scenarios 1+2]
→ T009
→ [US2 validation: Scenario 3]
→ T010 → T011 → T012 → T013 → T014 → T015
→ [US3 validation: Scenario 5]
→ T016 → T017
```

---

## Notes

- [P] tasks touch different files — safe to run concurrently
- US1 and US3 share the Phase 1+2 foundation but modify different scripts (`record-cost.sh` vs `report-cost.sh`) — can be worked in parallel by two developers after T001–T003 complete
- All rate resolution uses **per-M** internally; config per-1K values are multiplied ×1000 at resolution (see `data-model.md` § Rate Resolution State)
- The `model` field already exists in the ledger schema (v1) — no schema migration needed
- The `cost_usd` field continues to be written at record time for audit trail; `report-cost.sh` recomputes and ignores it
- OpenAI catalog entries are present but will not be auto-detected via the Wibey gateway (Anthropic-only). They support manual `--model gpt-5.4` recording by developers using OpenAI APIs directly.
- **⚠️ Commit grouping (Constitution §I)**: T001 (model-catalog.txt), T002 (catalog.sh), and T008 (extension.yml) MUST land in a single atomic commit. Do not commit T001/T002 before T008 — the manifest must always reflect the distributed config artifacts it declares.
- **Rate resolution duplication (I3)**: The FR-004 priority ladder is intentionally duplicated between `record-cost.sh` (T006) and `report-cost.sh` (T011). Add a comment in each script referencing the other: `# Rate resolution — same ladder in record-cost.sh / report-cost.sh. Update both if FR-004 priority changes.`
