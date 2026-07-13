---
description: "Task list for Cost Tracking Per Workflow Step with Cumulative Total"
---

# Tasks: Cost Tracking Per Workflow Step with Cumulative Total

**Input**: Design documents from `specs/001-cost-tracking-per-step/`

**Prerequisites**: plan.md ✅ | spec.md ✅ | research.md ✅ | data-model.md ✅ | contracts/ ✅ | quickstart.md ✅

**Tests**: Included — `bats-core` tests are declared in the plan (dev/CI only; runtime stays dependency-free per Constitution §V).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing.

## Format: `[ID] [P?] [Story?] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths in every description

## Path Conventions

Extension source layout at repository root:

```text
extension.yml               commands/          scripts/bash/lib/
config-template.yml         speckit.cost.*.md  scripts/bash/*.sh
tests/bats/*.bats           README.md          LICENSE
```

---

## Phase 1: Setup (Project Scaffolding)

**Purpose**: Create the extension skeleton and declare the full public contract before any implementation.

> **§I Extension Contract First**: `extension.yml` is authored here in full — commands, hooks, config — before any script is written.

- [x] T001 Create directory scaffold: `commands/`, `scripts/bash/lib/`, `tests/bats/`
- [x] T002 [P] Create `LICENSE` — MIT license, copyright `rnoap`, year 2026; add SPDX identifier `// SPDX-License-Identifier: MIT` comment template for scripts
- [x] T003 [P] Create `.extensionignore` — exclude `tests/`, `specs/`, `.specify/`, `*.bats`, `CHANGELOG.md` from extension distribution zip
- [x] T004 [P] Create `extension.yml` — complete manifest from `contracts/extension-manifest.md`: `schema_version: "1.0"`, `id: cost`, `name: spec-kit-cost`, `version: 1.0.0`, 3 commands (`speckit.cost.record/report/reset`), 3 config keys with defaults, 7 `after_*` hook wirings (CR-M1..CR-M5)
- [x] T005 [P] Create `config-template.yml` — 3 keys with documented defaults: `provider: self-report`, `price_per_1k: 0.003`, `model: unknown`; include inline comments explaining each key

**Checkpoint**: Extension manifest and config template authored — contract locked before implementation begins.

---

## Phase 2: Foundational (Shared Bash Library)

**Purpose**: Shared `lib/` scripts used by all three entry scripts. MUST be complete before any `*.sh` entry point is implemented.

**⚠️ CRITICAL**: No entry script (`record-cost.sh`, `report-cost.sh`, `reset-cost.sh`) can be written until this phase is complete.

- [x] T006 Create `scripts/bash/lib/json.sh` — two functions: `jsonl_emit` (assemble a schema-v1 record from named args using `printf`, escape `\` and `"` in free-text fields, strip newlines, emit one complete JSON line) and `jsonl_get_field` (extract a named field value from a JSONL line using `awk`/`grep`; no jq — implements research decision R1)
- [x] T007 [P] Create `scripts/bash/lib/config.sh` — function `config_get` that reads a `key: value` pair from `.specify/extensions/cost/cost-config.yml` using `grep`/`sed`; falls back to documented defaults when the file is absent or the key is missing (`provider=self-report`, `price_per_1k=0.003`, `model=unknown`); implements research decision R3
- [x] T008 [P] Create `tests/bats/` scaffold — `tests/bats/helpers/setup.bash` (shared setup: create temp dir, stub `.specify/feature.json` with `001-cost-tracking-per-step`, stub `cost-config.yml`); verify `bats-core` is installed or document install step in README

**Checkpoint**: Shared library ready — all entry scripts can now source `lib/json.sh` and `lib/config.sh`.

---

## Phase 3: User Story 1 — Per-step inline summary (Priority: P1) 🎯 MVP

**Goal**: After each of the 7 supported spec-kit lifecycle events, display exactly one inline cost summary line and append one JSONL record to the ledger.

**Independent Test**: Install the extension with no `cost-config.yml`. Complete any single `specify` step. Confirm `💰 specify: ~N in / ~N out tokens ≈ $N.NNNN` appears on stdout and one record exists in `.specify/extensions/cost/cost-ledger.jsonl`.

### Implementation for User Story 1

- [x] T009 [US1] Create `scripts/bash/record-cost.sh` — argument parser (`--step`, `--in-chars`, `--out-chars`, `--in-tokens`, `--out-tokens`, `--provider`, `--note`); provider resolution chain: `--provider` → `SPECKIT_COST_PROVIDER` → `config_get provider` → `self-report` (CR-R1); read `spec` from `.specify/feature.json` (CR-R3); **provider branch logic** (FR-012): (a) `self-report` — compute `input_tokens = ceil(in_chars/4)` and `output_tokens = ceil(out_chars/4)` via `awk` (FR-013); (b) `manual` — use `--in-tokens` and `--out-tokens` directly passed by the caller; (c) `log-file` — v1.0.0 stub: print `⚠️  speckit-cost: log-file provider not yet implemented — entry skipped` to stderr and `exit 0` (non-blocking per FR-015; documented in README as "planned for v1.1"); compute `cost_usd = (in+out)/1000 * price_per_1k` at 6dp via `awk` (CR-R4, R2); `mkdir -p` ledger dir; call `jsonl_emit` and append one line to `cost-ledger.jsonl` (CR-R5); print `💰 <step>: ~<in> in / ~<out> out tokens ≈ $<cost>` stripping `after_` prefix for display (CR-R6); on ANY failure print one stderr warning `⚠️  speckit-cost: <reason> — entry skipped` and `exit 0` (CR-R7); write only under `.specify/extensions/cost/` (CR-R8)
- [x] T010 [P] [US1] Create `commands/speckit.cost.record.md` — AI instruction file: determine the lifecycle event name from hook context (e.g., `after_specify`); **resolve active provider** from `SPECKIT_COST_PROVIDER` env or `cost-config.yml`; **provider branch**: (a) `self-report` — estimate character count of visible input content (prompt + spec files referenced) and output content (agent response for this step), invoke `bash scripts/bash/record-cost.sh --step <after_step> --in-chars <N> --out-chars <N>`; (b) `manual` — ask the developer "How many input/output tokens did this step use?" and pass the supplied counts: `bash scripts/bash/record-cost.sh --step <after_step> --provider manual --in-tokens <N> --out-tokens <N>`; (c) `log-file` — invoke `bash scripts/bash/record-cost.sh --step <after_step> --provider log-file` (script emits stub warning and skips, non-blocking); present script stdout to the developer; do not suppress stderr

### Tests for User Story 1

- [x] T011 [P] [US1] Create `tests/bats/record.bats` — SC-001: zero-config run produces exactly one inline summary line matching `^💰 specify:.*tokens.*\$`; SC-002: first-ever run with no `cost-config.yml` succeeds and appends one JSONL record; SC-007: simulate a write failure (read-only ledger dir) and assert exit code is still `0` and one stderr warning line appears

**Checkpoint**: User Story 1 is independently testable — zero-config inline summary working for all 7 hooks.

---

## Phase 4: User Story 2 — Cumulative cost breakdown (Priority: P2)

**Goal**: `speckit.cost.report` consolidates all recorded entries for the current spec into a per-step breakdown table plus cumulative USD total. Also fires automatically after `after_implement`.

**Independent Test**: With ≥2 recorded entries in the ledger for `001-cost-tracking-per-step`, invoke `speckit.cost.report` and confirm: (a) a markdown table with one row per entry appears, (b) the cumulative total equals the sum of per-step `cost_usd` values, (c) no rows from other specs appear.

### Implementation for User Story 2

- [x] T012 [US2] Create `scripts/bash/report-cost.sh` — read `spec` from `.specify/feature.json` unless `--spec` override given (CR-P1); filter `cost-ledger.jsonl` to lines where `"spec"` field matches (CR-P2); render a markdown table: header `| Step | Input | Output | Cost (USD) |`, one row per entry stripping `after_` prefix from step, columns right-aligned, cost at 4dp (CR-P3); compute cumulative total from stored 6dp values via `awk` and print as `**Total: $N.NNNN**` (CR-P4); MUST NOT write to ledger (CR-P5); when no entries match, print `No cost data recorded for this spec.` and exit 0 (CR-P6); runnable standalone with no hook dependency (CR-P7)
- [x] T013 [P] [US2] Create `commands/speckit.cost.report.md` — AI instruction file: invoke `bash scripts/bash/report-cost.sh`; present the complete output to the developer; note that this command is wired to `after_implement` (FR-007) and also available on demand (FR-006)

### Tests for User Story 2

- [x] T014 [P] [US2] Create `tests/bats/report.bats` — SC-003: seed ledger with 3 entries for current spec, run report, assert cumulative total = sum of per-step costs (awk float equality within 0.0001); SC-004: seed ledger with entries for two different specs, assert current spec report includes 0 rows from the other spec; SC-005: read `extension.yml` with `grep -A10 'after_implement'` and assert both `speckit.cost.record` and `speckit.cost.report` appear in that block in order (manifest contract check — POSIX grep only, no jq, per §V); SC-008: empty ledger produces `No cost data recorded for this spec.` message

**Checkpoint**: User Story 2 independently testable — report command works at any time, auto-fires after implement.

---

## Phase 5: User Story 3 — Safe reset (Priority: P3)

**Goal**: `speckit.cost.reset` clears recorded entries for the current spec, but only after explicit developer confirmation.

**Independent Test**: With existing ledger entries for `001-cost-tracking-per-step`, invoke `speckit.cost.reset`, decline the confirmation prompt, verify ledger is unchanged. Then invoke again, confirm, verify a subsequent `speckit.cost.report` shows the empty-state message.

### Implementation for User Story 3

- [x] T015 [US3] Create `scripts/bash/reset-cost.sh` — without `--yes`: print `Confirmation required — pass --yes to clear cost entries for <spec>` and exit 0 (CR-X1); with `--yes`: read all ledger lines, write lines whose `spec` field does NOT match current spec to a `mktemp` temp file (`tmp=$(mktemp)` + `trap "rm -f \"$tmp\"" EXIT` so the temp file is always cleaned up), then atomically `mv "$tmp" "$ledger"` (CR-X2, R4); **note on §II compliance**: the `mktemp` file is transient (sub-second lifetime, deleted by `trap` if `mv` fails) — it is a POSIX atomic-write idiom, not a durable write outside the extension dir; the durable write target is always `.specify/extensions/cost/cost-ledger.jsonl` (CR-X4); handle edge case: if no entries remain after filter, ledger becomes empty file (not deleted)
- [x] T016 [P] [US3] Create `commands/speckit.cost.reset.md` — AI instruction file: display a confirmation prompt to the developer explaining which spec's entries will be cleared and that the action is irreversible; wait for explicit confirmation (not a default); only if confirmed, invoke `bash scripts/bash/reset-cost.sh --yes`; if declined, report that no data was changed

### Tests for User Story 3

- [x] T017 [P] [US3] Create `tests/bats/reset.bats` — SC-006a: invoke `reset-cost.sh` without `--yes`, assert exit 0 and ledger is byte-for-byte unchanged; SC-006b: invoke `reset-cost.sh --yes`, assert the current spec's entries are removed from ledger while entries for other specs are preserved; SC-006c: after confirmed reset, run `report-cost.sh` and assert empty-state message

**Checkpoint**: All three user stories independently complete. Full spec workflow covered.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and release readiness.

- [x] T018 Create `README.md` — sections: Installation (`specify extension add cost --from <url>`), Zero-config quickstart, Provider guide (`self-report` default, `log-file` and `manual` configuration), Default values table (`provider: self-report`, `price_per_1k: 0.003`, `model: unknown`), `cost-config.yml` example, Community catalog note (spec-kit submission); English only
- [x] T019 [P] Update `CHANGELOG.md` — rename `## [Unreleased]` block to `## [1.0.0] - 2026-07-13`; add new empty `## [Unreleased]` section above it; add link definition `[1.0.0]: https://github.com/rnoap/spec-kit-cost/releases/tag/v1.0.0`
- [x] T020 [P] Verify `extension.yml` against `contracts/extension-manifest.md` — confirm all 5 CR-M rules pass: CR-M1 command IDs, CR-M2 all 3 commands + 7 hooks declared, CR-M3 `after_implement` chains record+report, CR-M4 3 config keys with correct defaults, CR-M5 schema_version + requires
- [x] T021 [P] Run `quickstart.md` validation scenarios — execute all 7 scenarios (SC-001..SC-008); confirm each expected output matches

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion (dir scaffold must exist)
- **User Story 1 (Phase 3)**: Depends on Phase 2 (lib/json.sh + lib/config.sh must exist)
- **User Story 2 (Phase 4)**: Depends on Phase 3 (ledger must be populated by record-cost.sh for report to work)
- **User Story 3 (Phase 5)**: Depends on Phase 3 (ledger must exist) — independent of Phase 4
- **Polish (Phase 6)**: Depends on all user story phases complete

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational — no dependency on US2 or US3
- **US2 (P2)**: Depends on US1 (needs ledger entries to test report correctly)
- **US3 (P3)**: Depends on US1 (needs ledger entries to test reset) — independent of US2

### Within Each Phase

- T006 → T007 and T008 can be parallel (different files)
- T009 depends on T006 and T007 (sources lib scripts)
- T010 and T011 can be parallel with each other (after T009)
- T012 depends on T006 and T007 (sources lib scripts)
- T013 and T014 can be parallel with each other (after T012)
- T015 depends on T006 and T007 (sources lib scripts)
- T016 and T017 can be parallel with each other (after T015)
- T018–T021 can all run in parallel (different files, no cross-dependencies)

---

## Parallel Opportunities Per Phase

```bash
# Phase 1 — run T002–T005 in parallel after T001
Task: "Create LICENSE"
Task: "Create .extensionignore"
Task: "Create extension.yml"
Task: "Create config-template.yml"

# Phase 2 — run T007 and T008 in parallel after T006
Task: "Create scripts/bash/lib/config.sh"
Task: "Create tests/bats/ scaffold"

# Phase 3 — run T010 and T011 in parallel after T009
Task: "Create commands/speckit.cost.record.md"
Task: "Create tests/bats/record.bats"

# Phase 4 — run T013 and T014 in parallel after T012
Task: "Create commands/speckit.cost.report.md"
Task: "Create tests/bats/report.bats"

# Phase 5 — run T016 and T017 in parallel after T015
Task: "Create commands/speckit.cost.reset.md"
Task: "Create tests/bats/reset.bats"

# Phase 6 — run T019–T021 in parallel after T018
Task: "Update CHANGELOG.md"
Task: "Verify extension.yml"
Task: "Run quickstart validation"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (lib scripts)
3. Complete Phase 3: US1 — per-step inline summary
4. **STOP and VALIDATE**: Install extension, run `specify`, confirm `💰` line appears and ledger entry written
5. Ship as a working extension

### Incremental Delivery

1. Setup + Foundational → shared foundation ready
2. US1 (record) → inline summary after every step (**MVP**; installable and valuable alone)
3. US2 (report) → cumulative breakdown on demand + auto after implement
4. US3 (reset) → safe ledger cleanup
5. Each story adds value without breaking previous stories

---

## Notes

- `[P]` = different files, no blocking dependencies → safe to run in parallel
- `[USn]` = maps task to specific user story for traceability
- Each entry script (`record`, `report`, `reset`) sources `lib/json.sh` and `lib/config.sh` — those libs are the only intra-extension coupling
- `extension.yml` is authored ONCE in Phase 1 (complete manifest per Constitution §I); no story phase should modify it
- The repo's own `.specify/extensions.yml` (which wires `git`/`brownfield` for building **this** repo) is entirely separate from the `extension.yml` product file
- All scripts: POSIX bash, `SPDX-License-Identifier: MIT`, English comments
- Tests use `bats-core` (dev/CI only); never referenced at runtime
