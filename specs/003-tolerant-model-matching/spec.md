# Feature Specification: Tolerant Model Matching and Split Fallback Rates

**Feature Branch**: `main` (implemented directly; documented retroactively)

**Created**: 2026-07-16

**Status**: Implemented — released as v1.3.0 (commit `5095b1e`)

**Input**: User report: "todavía el cálculo de costo no funciona bien y no mide el costo real y a veces no logra capturar el modelo para calcular bien el costo real" — observed as `analyze: ~6000 in / ~3000 out tokens ≈ $0.0270 (fallback rate used because model catalog entry not found)` while running GPT-5.3-Codex, whose catalog entry (`gpt-5.3-codex|1.75|14`) yields a true cost of $0.0525.

> **Note**: This spec documents work that was implemented and verified *before* the spec
> was written (retroactive SDD, no speckit workflow steps were run). It exists so the
> feature history, amendments to earlier specs, and acceptance evidence are on record.

## Problem Statement

Three defects compounded to make recorded costs wrong whenever the host agent supplied
anything other than an exact lowercase catalog ID:

1. **Case/format-sensitive catalog lookup** — `GPT-5.3-Codex` (GitHub Copilot UI label)
   never matched `gpt-5.3-codex`; the lookup was a literal, case-sensitive `grep`.
2. **Blended fallback underpriced output** — the fallback applied `price_per_1k`
   ($3/M) to *both* token types, while real output rates are 5–8× input rates. The
   config template documented split defaults ($3/M in, $15/M out) that the code never
   implemented, and shipped `price_per_1k: 0.003` active, pinning every unknown-model
   estimate to the blended rate.
3. **Silent degradation** — the catalog-miss warning went only to stderr, which agent
   harnesses routinely swallow; the raw (unresolvable) label was stored in the ledger,
   so `report-cost.sh` repricing failed for those entries too.

## User Scenarios & Testing

### User Story 1 - UI Display Labels Resolve to Catalog Entries (Priority: P1)

A developer runs a workflow step under GitHub Copilot with the model shown as
`GPT-5.3-Codex`. The cost hook passes that label via `--model`. The extension must
resolve it to the `gpt-5.3-codex` catalog entry and price the step at true rates.

**Acceptance Scenarios**:

1. **Given** the catalog contains `gpt-5.3-codex|1.75|14`, **When** the hook records
   6000 in / 3000 out with `--model 'GPT-5.3-Codex'`, **Then** cost is $0.0525 (not the
   $0.0270 blended fallback) and the ledger stores `"model":"gpt-5.3-codex"`.
2. **Given** a display name with spaces and dots (`Claude Sonnet 4.6`), **When**
   recorded, **Then** it resolves to `claude-sonnet-4-6`.
3. **Given** a dated/suffixed variant (`claude-opus-4-8-20260220`), **When** recorded,
   **Then** it resolves to `claude-opus-4-8` by longest dash-boundary prefix, and
   `gpt-5.4-mini-2026-01-01` resolves to `gpt-5.4-mini` (not `gpt-5.4`).

### User Story 2 - Honest, Visible Fallback for Unknown Models (Priority: P2)

A developer uses a model genuinely absent from the catalog. The estimate must use
realistic split defaults and the degradation must be visible inline, not only in stderr.

**Acceptance Scenarios**:

1. **Given** no catalog match and no explicit `price_per_1k`, **When** a step is
   recorded, **Then** rates are $3/M input and $15/M output (split defaults).
2. **Given** a *named* model misses the catalog, **When** the 💰 summary prints,
   **Then** it ends with `(fallback rate — "<model>" not in catalog)`.
3. **Given** the model is `unknown` (never detected), **When** the summary prints,
   **Then** the original format is preserved exactly (no marker) — spec 001 SC-001
   remains satisfied for this case.
4. **Given** `price_per_1k` **is** explicitly set in `cost-config.yml`, **When** no
   catalog match exists, **Then** the legacy blended formula applies unchanged
   (backward compatibility with spec 002 US2/AS2).

### User Story 3 - Real Token Counts When the Host Exposes Them (Priority: P3)

When the host agent surfaces actual token usage for a step, the recording command
should pass those real numbers via `--in-tokens`/`--out-tokens` instead of the
chars ÷ 4 heuristic. (Documentation/prompt change; the script already accepted
direct token counts.)

## Requirements

### Functional Requirements

- **FR-001**: `catalog_get_rates` MUST resolve model labels through a matching ladder,
  first hit wins: (1) exact ID; (2) normalized — lowercase, trimmed, trailing
  parenthetical stripped, spaces/underscores → dashes, repeated dashes collapsed;
  (3) normalized with dots → dashes; (4) longest catalog ID that is a dash-boundary
  prefix of the candidate.
- **FR-002**: `record-cost.sh` MUST store the *canonical resolved* catalog ID in the
  ledger `model` field when resolution succeeds; the raw label is stored only when no
  match exists.
- **FR-003**: When no config per-type override and no catalog match apply, and
  `price_per_1k` is **not** explicitly set, rates MUST default to $3/M input and
  $15/M output. An explicitly set (valid numeric) `price_per_1k` preserves the legacy
  blended behavior.
- **FR-004**: `config-template.yml` MUST ship with `price_per_1k` commented out
  (opt-in), so the split defaults and catalog govern fresh installs.
- **FR-005**: When a named (non-`unknown`) model misses the catalog, the inline 💰
  summary MUST append ` (fallback rate — "<model>" not in catalog)` in addition to the
  stderr warning. For `unknown` or matched models the spec-001 format is unchanged.
- **FR-006**: `report-cost.sh` MUST apply the identical matching ladder and split
  defaults when repricing, so legacy ledger entries recorded with display labels
  reprice correctly once the catalog can resolve them.
- **FR-007**: The recording command prompt (`commands/speckit.cost.record.md` and its
  installed skill copy) MUST document GitHub Copilot display-label handling and MUST
  instruct agents to prefer real token counts via `--in-tokens`/`--out-tokens` when the
  host exposes actual usage.
- **FR-008**: Catalog parsing MUST remain pure POSIX shell utilities (awk field
  comparison replaces the previous grep pipeline; no regex-injection surface).

## Amendments to Earlier Specs

| Artifact | Statement superseded | Replacement |
|---|---|---|
| 001 `spec.md` FR-002 / SC-001 | Summary line always matches `💰 <step>: … ≈ $N.NNNN` exactly | Format preserved for matched/`unknown` models; named catalog misses append the FR-005 fallback marker |
| 002 `spec.md` FR-004 (rung 4) / Edge case | "hardcoded default **blended** rate" | Split defaults: $3/M input, $15/M output (FR-003) |
| 002 `data-model.md` §Lookup Semantics | "**exact match only** in v1 to avoid false positives" | Matching ladder of FR-001 (v1.3.0) |
| 002 `contracts/catalog-format.md` §Lookup Algorithm | grep-based exact-match snippet | awk exact-field lookup + resolution ladder |
| 002 `contracts/config-schema.md` | `price_per_1k` default `0.003` | No default — opt-in; absent ⇒ split defaults |
| 002 `quickstart.md` Scenario 4 | Unknown model costs $0.0021 (blended 3/M both) | $0.0045 (500×3/1M + 200×15/1M) + inline marker |

## Success Criteria

- **SC-001**: The originally reported failure (`GPT-5.3-Codex`, 6000 in / 3000 out)
  records $0.0525 and stores `gpt-5.3-codex` — verified by smoke test and bats.
- **SC-002**: `report-cost.sh` reprices a legacy ledger entry stored as
  `"model":"GPT-5.3-Codex"` at catalog rates ($0.0088 for 1000/500) — verified by bats.
- **SC-003**: All 17 new/updated bats cases pass (36 total; the 5 remaining failures
  are pre-existing Windows environment artifacts: 💰-emoji grep locale, `chmod 000`
  no-op — confirmed identical on the pre-change code).
- **SC-004**: No new runtime dependencies; implementation remains bash + POSIX
  utilities (Constitution §V).

## Evidence

- Implementation + tests + docs: commit `5095b1e` (v1.3.0, 2026-07-16).
- End-to-end verification against the reinstalled dev copy
  (`.specify/extensions/cost/`): `💰 analyze: ~6000 in / ~3000 out tokens ≈ $0.0525`.
- CHANGELOG entry: `## [1.3.0] - 2026-07-16`.
