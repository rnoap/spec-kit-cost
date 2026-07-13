# Phase 1 Data Model: Cost Tracking Per Workflow Step

**Feature**: `001-cost-tracking-per-step` | **Date**: 2026-07-13

This document defines the durable data shapes. The **Cost Entry** schema is **fixed by
the project constitution (§IV, record schema v1)** and by FR-018; it is reproduced here
field-for-field and MUST NOT be altered without a constitution amendment and a `"v"` bump.

---

## Entity: Cost Entry (record schema v1)

One JSON object per line in the ledger, one entry per lifecycle event occurrence.

**Canonical record (verbatim from Constitution §IV):**

```json
{
  "v": 1,
  "ts": "2026-07-13T12:00:00Z",
  "step": "after_specify",
  "spec": "001-my-feature",
  "provider": "self-report",
  "input_tokens": 1200,
  "output_tokens": 800,
  "model": "claude-sonnet-4",
  "cost_usd": 0.0024,
  "note": ""
}
```

### Field specification

| Field | JSON type | Required | Description | Source / Constraint |
|-------|-----------|----------|-------------|---------------------|
| `v` | integer | yes | Schema version. Fixed at `1` for this feature. | Constitution §IV; bump only on field-semantics change |
| `ts` | string | yes | UTC timestamp, ISO-8601 with trailing `Z`. | `date -u +%Y-%m-%dT%H:%M:%SZ`; FR-018 |
| `step` | string | yes | Lifecycle event name. One of the seven `after_*` events. | FR-001; **stored with `after_` prefix** (see note below) |
| `spec` | string | yes | Spec identifier = feature directory name. | FR-004; read from `.specify/feature.json` |
| `provider` | string | yes | Data source used. One of `self-report`, `log-file`, `manual`. | FR-012; Constitution §III |
| `input_tokens` | integer | yes | Estimated input token count. | FR-013 (`chars ÷ 4`) with `self-report` |
| `output_tokens` | integer | yes | Estimated output token count. | FR-013 (`chars ÷ 4`) with `self-report` |
| `model` | string | yes | Model label. Defaults to `unknown` when unconfigured. | FR-018; config `model` key |
| `cost_usd` | number | yes | Computed cost in USD. Stored at 6 decimal places. | FR-018; `(in+out)/1000 * price_per_1k` |
| `note` | string | no | Optional free-text note; empty string when unused. | FR-018 (optional attribute) |

**Field order in emitted records**: `v, ts, step, spec, provider, input_tokens,
output_tokens, model, cost_usd, note` — matches the constitution's canonical example.

### `step` storage vs display (explicit decision)

- **Stored** value keeps the full event name: `after_specify`, `after_clarify`,
  `after_plan`, `after_tasks`, `after_analyze`, `after_checklist`, `after_implement`
  (matches Constitution §IV example `"step": "after_specify"`).
- **Displayed** value in the inline summary (FR-002) strips the `after_` prefix:
  `after_specify` → `specify`. This reconciles the schema (`after_specify`) with the
  required summary format `💰 <step>: ...` where `<step>` is `specify`.

### Validation rules

- `input_tokens` and `output_tokens` MUST be non-negative integers. If either cannot be
  produced, **no entry is written** (FR-015) — partial/error records are never persisted.
- `cost_usd` is always derived, never supplied directly, ensuring it is consistent with
  the token counts and configured price.
- `step` MUST be one of the seven enumerated `after_*` values; any other value is a
  programming error in the hook wiring, not a valid entry.
- Free-text fields (`spec`, `model`, `note`) are JSON-escaped (`\` and `"`) and stripped
  of newlines before emission, preserving the one-record-per-line invariant.

---

## Entity: Cost Ledger

The append-only collection of Cost Entries.

| Attribute | Value |
|-----------|-------|
| Location | `.specify/extensions/cost/cost-ledger.jsonl` (fixed by constitution) |
| Format | JSON Lines — one Cost Entry object per line |
| Mutability | Append-only during recording; full rewrite permitted **only** by `speckit.cost.reset` |
| Multi-spec | MAY contain entries from multiple specs; the `spec` field distinguishes them (FR-004) |
| Creation | Created lazily on first successful record; parent dir `mkdir -p` first |

**Invariants**:

- Recording never modifies or deletes an existing line (Constitution §IV, FR-003).
- Every line is a complete, valid JSON object (guaranteed by full-line assembly before a
  single append — R4).
- An interrupted append leaves the ledger with only whole prior lines (append-only audit
  trail; edge case "Interrupted step").

---

## Entity: Cost Configuration

Developer-adjustable settings governing computation and collection.

| Attribute | Config key | Type | Default (zero-config) | Requirement |
|-----------|-----------|------|-----------------------|-------------|
| Active provider | `provider` | enum | `self-report` | FR-012, Constitution §III |
| Price per 1K tokens | `price_per_1k` | number (USD) | `0.003` | FR-011 |
| Default model label | `model` | string | `unknown` | FR-018, Assumptions |

| Attribute | Value |
|-----------|-------|
| Location | `.specify/extensions/cost/cost-config.yml` (fixed by constitution) |
| Absent behavior | All keys fall back to defaults above → zero-config operation (FR-014) |
| Provider override | `SPECKIT_COST_PROVIDER` env var, then per-invocation argument, take precedence |

**Provider enum values**: `self-report` (default), `log-file`, `manual` (Constitution §III).

---

## Entity: Cost Report (derived, non-persistent)

A read-only projection consolidated from the ledger for a single spec. Never written back
to the ledger (FR-010, Constitution §IV).

**Structure**:

- Per-step breakdown table: one row per recorded entry for the current spec, showing step
  name, `input_tokens`, `output_tokens`, and per-step `cost_usd`.
- Cumulative total: sum of `cost_usd` across the current spec's entries, in USD (FR-005).

**Rules**:

- Includes only entries whose `spec` matches the current feature directory name (FR-004,
  SC-004) — 0 rows from other specs.
- When the current spec has no entries, renders the explicit empty-state message instead
  of an empty table (FR-017, SC-008).
- Cumulative total equals the sum of the displayed per-step costs (SC-003); computed from
  6-decimal stored values, displayed at 4 decimals.

---

## Relationships

```text
Cost Configuration ──governs──▶ cost computation for each Cost Entry
Cost Entry ──appended to──▶ Cost Ledger (many entries, many specs)
Cost Ledger ──filtered by spec + summed──▶ Cost Report (one per spec, read-only)
```
