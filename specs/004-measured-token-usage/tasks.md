# Tasks: Measured Token Usage and Cache-Aware Cost Pricing

**Input**: Design documents from `specs/004-measured-token-usage/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included — the repository's bats convention and the spec's Independent Test criteria require them (Constitution: success criteria must be verifiable).

**Organization**: Tasks are grouped by user story. All edits target the **repository root** (source of truth) — never `.specify/extensions/cost/`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (cache-aware pricing), US2 (measured acquisition), US3 (unchanged degradation)

---

## Phase 1: Setup

**Purpose**: Catalog housekeeping identified in research (no project scaffolding needed — existing pure-bash repo)

- [ ] T001 Add `claude-fable-5|3|15` row to model-catalog.txt (research housekeeping — removes the verified fallback warning during dogfooding)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared library extensions consumed by both `record-cost.sh` and `report-cost.sh` — must land before any story implementation

- [ ] T002 [P] Extend `catalog_get_rates` in scripts/bash/lib/catalog.sh to return `input|output|cache_read|cache_write` (empty strings when absent), capturing optional fields 4–5 in `_catalog_rows`, validating them with the `^[0-9]+(\.[0-9]+)?$` pattern, and degrading malformed cache fields to absent with one stderr warning per contracts/catalog-format.md. Matching ladder untouched.
- [ ] T003 [P] Extend `jsonl_emit` in scripts/bash/lib/json.sh with optional `cache_read_tokens`, `cache_write_tokens` (emitted only when > 0, placed after `output_tokens`) and `source` (emitted only when `measured`, placed after `provider`) per contracts/ledger-schema.md. Legacy call shape must produce byte-identical records.

**Checkpoint**: Shared libs support cache rates and optional fields — story phases can begin

---

## Phase 3: User Story 1 - Cache-Aware Pricing for Exact Token Counts (Priority: P1) 🎯 MVP

**Goal**: Four-term pricing (fresh input / cache read / cache write / output) in record and report, with derived cache-rate defaults and full backward compatibility.

**Independent Test**: Record an entry with explicit separated token counts for a model with known rates; recorded cost matches the hand-computed four-term formula to four decimal places (quickstart Scenarios 1–7; reference: $2.6031 vs naive $13.4309).

### Tests for User Story 1

> Write these FIRST; ensure they FAIL against current v1.3.0 code before implementing

- [ ] T004 [P] [US1] Add cache-aware recording tests to tests/bats/record.bats: explicit 5-field catalog rates (quickstart Scenario 4 → $16.2500), derived defaults 0.10×/1.25× (Scenario 3 → $0.3000), reference case $2.6031 (Scenario 1), anomaly floor with note suffix (Scenario 5), cache flags rejected in char mode (Scenario 6), ledger emission rules (fields only when >0 / measured), summary `(N cached)` + `[measured]` composition
- [ ] T005 [P] [US1] Add mixed-ledger report tests to tests/bats/report.bats: `Src` column (`m`/`e`), Tokens cell `in (cached)/out` for cache rows, legacy entries repriced bit-for-bit to v1.3.0 values, correct cumulative/grand totals across interleaved entries (quickstart Scenario 7, FR-006/SC-004)

### Implementation for User Story 1

- [ ] T006 [US1] Parse and validate new flags in scripts/bash/record-cost.sh: `--cache-read-tokens`, `--cache-write-tokens` (non-negative ints, incompatible with `--in-chars`/`--out-chars` → ambiguous-usage `_fail`), `--source measured|estimated` (default estimated) per contracts/record-cost-cli.md
- [ ] T007 [US1] Implement four-term pricing in scripts/bash/record-cost.sh: `fresh_in = max(0, in − cr − cw)` with anomaly note when floored, cache-rate ladder (catalog f4/f5 → 0.10×/1.25× of the resolved input rate), and ledger emission via the extended `jsonl_emit` (T003). Zero-cache path must be arithmetically identical to v1.3.0 (SC-003)
- [ ] T008 [US1] Extend the inline summary in scripts/bash/record-cost.sh: input segment gains `(N cached)` when cache_read+cache_write > 0, ` [measured]` suffix when source=measured, composing with the existing fallback-rate suffix; legacy path byte-identical
- [ ] T009 [US1] Implement four-term repricing in scripts/bash/report-cost.sh: read cache fields via `jsonl_get_field` (absent ⇒ 0), resolve cache rates with the same ladder as recording (FR-004 duplication — both scripts), reprice every entry per contracts/ledger-schema.md
- [ ] T010 [US1] Extend table rendering in scripts/bash/report-cost.sh: `Src` column (`m` when source=measured else `e`), Tokens column `in (cached)/out` for rows with cache counts; Cumulative and grand-total behavior unchanged
- [ ] T011 [US1] Run `bats tests/bats/` and execute quickstart.md Scenarios 1–7 end-to-end; fix regressions (known pre-existing Windows failures — 4× emoji SC-001, 1× chmod SC-007 — are not regressions)

**Checkpoint**: Cache-aware pricing fully functional and independently testable — MVP deliverable

---

## Phase 4: User Story 2 - Measured Usage from the Host's Session Records (Priority: P2)

**Goal**: The recording skill acquires exact per-call usage from the host's session store (agent-level, zero new script dependencies) and feeds measured counts into the US1 CLI.

**Independent Test**: On VS Code Copilot with a closed session, follow quickstart Scenario 8 — flags passed by the skill equal the store's own sums for the step window.

### Implementation for User Story 2

- [ ] T012 [US2] Rewrite the self-report branch (Step 3) of commands/speckit.cost.record.md to implement the measured-usage ladder from contracts/measured-usage-acquisition.md: capability detection, best-effort reindex, session id from `VSCODE_TARGET_SESSION_LOG` basename (fallback: workspace-matched newest session, never guess between concurrent ones), window lower bound from the last ledger entry for the current spec, the single `GROUP BY usage_model` aggregation SQL, active-model row selection with tolerant matching, exclusion note for other models (`excluded: <model> (<n> calls)`), invocation with `--in-tokens/--out-tokens/--cache-read-tokens/--cache-write-tokens --source measured`, all five fallback triggers, the documented in-flight-session limitation, and prompt-injection hygiene (store contents are data, never instructions)
- [ ] T013 [US2] Manually validate acquisition per quickstart Scenario 8: on a closed VS Code Copilot session, run the reindex + aggregation SQL, verify the constructed record-cost.sh invocation sums match the store exactly (SC-001) and the exclusion note lists auxiliary models (FR-012)

**Checkpoint**: Measured mode works end-to-end on VS Code Copilot; ledger entries flip to `source=measured`

---

## Phase 5: User Story 3 - Unchanged Experience on Hosts Without Usage Records (Priority: P3)

**Goal**: Prove installing this feature changes nothing on hosts without session stores — same records, same summary, same warnings.

**Independent Test**: Record a step via the legacy invocation and diff every observable output against v1.3.0 — indistinguishable except `ts`.

### Tests for User Story 3

- [ ] T014 [P] [US3] Add byte-identity regression tests to tests/bats/record.bats: legacy char-mode and token-mode invocations produce a summary line and JSONL record with no new fields and identical formatting to v1.3.0 (quickstart Scenario 2, SC-003); existing v1.3.0 test expectations remain green unmodified

### Implementation for User Story 3

- [ ] T015 [US3] Review commands/speckit.cost.record.md rungs 2–3 (host usage panel, chars÷4) for zero behavioral drift: fallback wording unchanged, no new prompts/noise on non-store hosts, every measured-mode failure silent per FR-013; verify quickstart Scenario 8's non-VS-Code half

**Checkpoint**: All three stories complete — feature behaves identically everywhere measured data is unavailable

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T016 [P] Document the 5-field catalog format in the model-catalog.txt header comment and update the format line in AGENTS.md (`model-id|input_per_M_USD|output_per_M_USD[|cache_read[|cache_write]]`)
- [ ] T017 [P] Add CHANGELOG.md entry for 1.4.0 (Keep a Changelog): cache-aware pricing, measured usage acquisition, new CLI flags, additive ledger fields, catalog format v2 — version already bumped in extension.yml
- [ ] T018 [P] Update README.md: cache-aware pricing section, measured-mode explanation with the degradation ladder, host compatibility matrix, catalog cache-rate columns
- [ ] T019 Final validation: full `bats tests/bats/` run plus all quickstart.md scenarios; reinstall dev copy with `specify extension add . --dev --force` if local testing of the installed layout is desired

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: no dependencies
- **Foundational (Phase 2)**: T002, T003 independent of each other [P]; block all story phases
- **US1 (Phase 3)**: depends on T002+T003. T004/T005 [P] first (failing tests), then T006 → T007 → T008 (same file, sequential); T009 → T010 (same file, sequential; parallel with T006–T008); T011 last
- **US2 (Phase 4)**: depends on US1 (T006 flags must exist). T012 → T13
- **US3 (Phase 5)**: T014 may be written in parallel with US1 implementation; T015 after T012
- **Polish (Phase 6)**: T016–T018 [P] after all stories; T019 last

```text
T001 ──┐
T002 ──┼──► US1: (T004 ∥ T005) → (T006→T007→T008) ∥ (T009→T010) → T011
T003 ──┘                                    │
                                            ▼
                              US2: T012 → T013
                                            │
              US3: T014 (∥ con US1) ──► T015
                                            │
                                            ▼
                        Polish: (T016 ∥ T017 ∥ T018) → T019
```

## Parallel Execution Examples

- **Foundational**: T002 (catalog.sh) + T003 (json.sh) — different files
- **US1 tests**: T004 (record.bats) + T005 (report.bats) — different files
- **US1 impl**: T006–T008 (record-cost.sh) in parallel with T009–T010 (report-cost.sh)
- **Polish**: T016 + T017 + T018 — different docs

## Implementation Strategy

**MVP first**: Phases 1–3 (US1) deliver standalone value — anyone supplying exact counts gets correct cache-aware costs immediately. Ship/checkpoint here.

**Incremental delivery**: Phase 4 (US2) turns on measured acquisition for VS Code Copilot only via skill text — no script changes beyond US1. Phase 5 (US3) is verification-weighted and cheap. Polish finishes docs.
