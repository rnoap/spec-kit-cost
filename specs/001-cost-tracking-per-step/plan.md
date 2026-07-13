# Implementation Plan: Cost Tracking Per Workflow Step with Cumulative Total

**Branch**: `001-cost-tracking-per-step` | **Date**: 2026-07-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-cost-tracking-per-step/spec.md`

## Summary

Build a spec-kit **extension** (not an app or service) that hooks into all seven spec-kit
`after_*` lifecycle events, estimates the LLM token cost of each step, appends an
append-only JSONL ledger, prints a one-line inline cost summary after each step, and
renders a per-spec breakdown table plus cumulative USD total (automatically after
`implement`, or on demand). Provides `record`, `report`, and `reset` commands. Default
data source is `self-report` (`chars ÷ 4` heuristic) with a configurable
price-per-1k-tokens. The technical approach is **shell-first**: all persistence and math
live in POSIX bash scripts (no jq/python/node at runtime); markdown command files carry
AI-executed instructions only.

## Technical Context

**Language/Version**: POSIX-compatible Bash (no bash-5-only features without a guard).

**Primary Dependencies**: None at runtime — standard POSIX utilities only (`awk`, `sed`,
`grep`, `date`, `printf`, `mktemp`, `mv`). Dev/CI only: `bats-core` test harness.

**Storage**: Append-only JSON Lines ledger at
`.specify/extensions/cost/cost-ledger.jsonl`; flat YAML config at
`.specify/extensions/cost/cost-config.yml`.

**Testing**: `bats-core` (dev/CI only; never invoked at runtime — preserves Principle V).

**Target Platform**: Any environment running spec-kit `>= 0.4.0` with a POSIX shell
(Linux, macOS; Windows parity via `scripts/powershell/` deferred to a v1.1 MINOR release).

**Project Type**: spec-kit extension (manifest + AI command files + bash scripts + config
template). Not a single-app source tree.

**Performance Goals**: Per-step overhead negligible (a few shell/awk invocations per
event); no measurable impact on the primary workflow step.

**Constraints**: Write isolation to `.specify/extensions/cost/` only; cost tracking MUST
never block or fail the primary workflow step (hooks exit 0); zero-config operation using
documented defaults (`self-report`, `$0.003/1K`, model `unknown`).

**Scale/Scope**: Single project (per repository); 3 commands, 3 bash scripts, 7 hook
wirings, 1 manifest, 1 config template. Cross-repo aggregation is out of scope.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

Constitution: `.specify/memory/constitution.md` v1.0.0.

| # | Principle | Gate | Design compliance |
|---|-----------|------|-------------------|
| I | Extension Contract First | `extension.yml` declares every command, hook, and config key before implementation; command IDs match `speckit.cost.<action>`; `schema_version` `"1.0"`. | [contracts/extension-manifest.md](./contracts/extension-manifest.md) fixes the full manifest (CR-M1..M5). |
| II | Non-Destructive Tracking (NON-NEGOTIABLE) | Writes only under `.specify/extensions/cost/`; no `git add/commit`/`rm` on spec/source files; hook scripts exit 0 on failure. | CR-G1, CR-G2, CR-R7, CR-R8; ties to FR-015/FR-016. |
| III | Pluggable Data Source | Provider decoupled from persistence; default `self-report`; `SPECKIT_COST_PROVIDER` override. | CR-R1 provider resolution order; providers `self-report`/`log-file`/`manual`. |
| IV | Append-Only Ledger | JSONL append-only; only `reset` truncates (with confirmation); `report` never writes; record schema v1 unchanged. | data-model.md reproduces schema verbatim; CR-R5, CR-P5, CR-X3, CR-G3, CR-G4. |
| V | Shell-First, Zero Runtime Deps | All persistence/math in POSIX bash; no jq/python/node at runtime; `.md` files contain no inline shell. | research.md R1–R4 (jq-free JSONL, awk math, parser-free YAML, atomic ops); `bats` is dev-only (R5); CR-G5. |

**Compatibility constraints**: spec-kit `>=0.4.0`; MIT license (SPDX in every source
file); repository `https://github.com/rnoap/spec-kit-cost`; all docs/comments in English.

**Initial gate result**: PASS — no violations; Complexity Tracking not required.

**Post-design re-check**: PASS — Phase 1 artifacts introduce no deviation. The record
schema in data-model.md matches Constitution §IV field-for-field; no new fields, no new
runtime dependency, no write outside the extension data directory.

## Project Structure

### Documentation (this feature)

```text
specs/001-cost-tracking-per-step/
├── plan.md              # This file (/speckit-plan output)
├── research.md          # Phase 0: shell-first technical decisions
├── data-model.md        # Phase 1: Cost Entry (schema v1), Ledger, Config, Report
├── quickstart.md        # Phase 1: runnable validation scenarios
├── contracts/           # Phase 1: manifest + command/script contracts
│   ├── extension-manifest.md
│   └── commands.md
├── checklists/
│   └── requirements.md  # spec quality checklist (16/16)
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created here)
```

### Source Code (extension repository)

The extension is authored at the **repository root** (source layout) and provisions a
**runtime layout** under `.specify/extensions/cost/` on install.

```text
# Source layout (authored, committed to the repo)
extension.yml                     # manifest — single source of truth (§I)
config-template.yml               # default config; installed as cost-config.yml
commands/
├── speckit.cost.record.md        # AI instructions: estimate content, invoke record-cost.sh
├── speckit.cost.report.md        # AI instructions: invoke report-cost.sh, present output
└── speckit.cost.reset.md         # AI instructions: confirm, then invoke reset-cost.sh --yes
scripts/
└── bash/
    ├── record-cost.sh            # provider resolve, chars÷4, cost math (awk), JSONL append
    ├── report-cost.sh            # read-only: filter by spec, breakdown table + total
    ├── reset-cost.sh             # confirmation-gated per-spec ledger rewrite (temp + mv)
    └── lib/
        ├── config.sh             # flat YAML key reader + default resolution (R3)
        └── json.sh               # JSONL emit (escape + printf) + field extract (R1)
tests/
└── bats/
    ├── record.bats               # SC-001, SC-002, SC-007
    ├── report.bats               # SC-003, SC-004, SC-005, SC-008
    └── reset.bats                # SC-006
README.md                         # zero-config usage, providers, defaults (English)
CHANGELOG.md                      # already present (Keep a Changelog)
LICENSE                           # MIT

# Runtime layout (created on install / at first run)
.specify/extensions/cost/
├── cost-config.yml               # from config-template.yml (optional; defaults if absent)
├── cost-ledger.jsonl             # append-only ledger (created lazily on first record)
└── scripts/bash/...              # installed copies invoked by hooks/commands
```

**Structure Decision**: A spec-kit extension source layout (manifest + `commands/` +
`scripts/bash/` + `config-template.yml`) is used, matching spec-kit extension conventions
and Constitution §V. Shared bash logic is factored into `scripts/bash/lib/` so the three
entry scripts stay small and each POSIX concern (config reading, JSON emit/parse) is
isolated and testable. The runtime layout under `.specify/extensions/cost/` is the only
place the extension writes (Constitution §II).

## Design Detail

### Command ↔ script design

| Command (`.md`) | Delegates to | Responsibility split |
|-----------------|--------------|----------------------|
| `speckit.cost.record` | `record-cost.sh` | `.md` derives step name from the firing event and (for `self-report`) estimates visible input/output content sizes, then invokes the script. Script resolves provider/price/model, computes `chars ÷ 4` and cost via `awk`, appends one JSONL record, prints the inline summary. Always exits 0. |
| `speckit.cost.report` | `report-cost.sh` | `.md` invokes the script and presents output. Script filters ledger to the current spec, renders the breakdown table + cumulative total; read-only; empty-state message when no entries. |
| `speckit.cost.reset` | `reset-cost.sh` | `.md` obtains explicit human confirmation, then calls the script with `--yes`. Script rewrites the ledger removing only the current spec's lines (temp file + atomic `mv`); refuses without `--yes`. |

Full argument-level interface and behavior rules are fixed in
[contracts/commands.md](./contracts/commands.md) (CR-R*, CR-P*, CR-X*, CR-G*).

### Data model

The **Cost Entry** record schema is fixed by Constitution §IV (schema v1) and FR-018 and
is reproduced verbatim in [data-model.md](./data-model.md). Key points:

- Fields (in emission order): `v, ts, step, spec, provider, input_tokens, output_tokens,
  model, cost_usd, note`.
- `step` is **stored** with the `after_` prefix (`after_specify`) but **displayed** with
  the prefix stripped (`specify`) in the inline summary — reconciling §IV with FR-002.
- `cost_usd` stored at 6 decimals, displayed at 4, so the report total equals the sum of
  per-step costs (SC-003).
- Ledger is append-only JSONL; Config is a flat three-key YAML with documented defaults;
  Report is a read-only per-spec projection.

### Hook wiring strategy

Hooks are declared in the extension's **own `extension.yml`** (distinct from this repo's
`.specify/extensions.yml`, which wires git/brownfield to *build* this repo):

| Event | Command(s) fired | Requirement |
|-------|------------------|-------------|
| `after_specify` | `speckit.cost.record` | FR-001 |
| `after_clarify` | `speckit.cost.record` | FR-001 |
| `after_plan` | `speckit.cost.record` | FR-001 |
| `after_tasks` | `speckit.cost.record` | FR-001 |
| `after_analyze` | `speckit.cost.record` | FR-001 |
| `after_checklist` | `speckit.cost.record` | FR-001 |
| `after_implement` | `speckit.cost.record`, then `speckit.cost.report` | FR-001, FR-007, SC-005 |

Every `after_*` event records one entry and shows the inline summary; `after_implement`
additionally auto-renders the full cumulative breakdown. All hook-invoked scripts exit 0
even on failure so the primary workflow is never blocked (FR-015, Constitution §II).

### Key resolved decisions (from research.md — Phase 0)

- **JSONL without jq**: `printf` emit with pre-escaped free-text fields; field-scoped
  `awk`/`grep`/`sed` parse (records are flat, self-emitted, one per line). — R1
- **Float math in shell**: `awk` doubles; store 6dp, display 4dp (bash has no floats). — R2
- **YAML config without a parser**: flat `grep`/`sed` `key: value` extractor; missing file
  or key → documented defaults (`self-report`, `0.003`, `unknown`). — R3
- **Atomic writes**: single-line `>>` append for records; temp file + `mv` for reset. — R4
- **Testing**: `bats-core` at dev/CI time only; runtime stays dependency-free. — R5

## Complexity Tracking

No constitutional violations. No entries required.

## Phase Outputs

- **Phase 0** → [research.md](./research.md) — all NEEDS CLARIFICATION resolved.
- **Phase 1** → [data-model.md](./data-model.md), [contracts/](./contracts/),
  [quickstart.md](./quickstart.md).
- **Phase 2** → `tasks.md` — produced by `/speckit-tasks` (not created by this command).
