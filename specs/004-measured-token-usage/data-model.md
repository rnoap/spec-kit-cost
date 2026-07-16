# Data Model: Measured Token Usage and Cache-Aware Cost Pricing

**Feature**: `004-measured-token-usage` | **Date**: 2026-07-16
**Sources**: [spec.md](spec.md) Key Entities, [research.md](research.md) D2/D4/D5

## Cost Entry (extended)

One appended JSONL record per completed workflow step. Schema stays `"v": 1`
(research D5) — the three new fields are additive and optional.

| Field | Type | Required | Meaning / rules |
|---|---|---|---|
| `v` | int | yes | Schema version. Remains `1`. |
| `ts` | string (UTC ISO-8601) | yes | Unchanged. |
| `step` | string | yes | Unchanged (`after_*`, validated enum). |
| `spec` | string | yes | Unchanged (feature directory basename). |
| `provider` | string | yes | Unchanged (`self-report` \| `manual` \| `log-file`). |
| `input_tokens` | int ≥ 0 | yes | **Total** input tokens, inclusive of cached tokens — historical meaning unchanged (research D4). |
| `output_tokens` | int ≥ 0 | yes | Unchanged. |
| `cache_read_tokens` | int ≥ 0 | no | NEW. Cache-read subset of `input_tokens`. Emitted only when > 0. Absent ⇒ 0. |
| `cache_write_tokens` | int ≥ 0 | no | NEW. Cache-write subset of `input_tokens`. Emitted only when > 0. Absent ⇒ 0. |
| `source` | string | no | NEW. Emitted only with value `"measured"` (host-reported counts). Absent ⇒ estimated (FR-008). |
| `model` | string | yes | Unchanged (canonical resolved ID or raw label / `unknown`). |
| `cost_usd` | float ≥ 0 | yes | Unchanged field; now computed by the four-term formula below. |
| `note` | string | yes (may be empty) | Unchanged. Carries excluded-model mentions (FR-012) and anomaly notes. |

**Validation rules** (enforced by the recording script, non-blocking `_fail` on
violation):

- `cache_read_tokens`, `cache_write_tokens`: non-negative integers when provided.
- Cache flags are only meaningful with direct token counts; combining them with
  character-based inputs is rejected as ambiguous (mirrors the existing mixed
  chars/tokens guard).
- `source`: `measured` or `estimated` only; anything else rejected.

**Derived value (never stored)**:

```text
fresh_input = max(0, input_tokens − cache_read_tokens − cache_write_tokens)
```

If `cache_read + cache_write > input_tokens` (host anomaly, spec edge case), the
floor applies and the entry's `note` records the anomaly.

**Pricing invariant** (record and report MUST agree — the ladder is duplicated in
both scripts):

```text
cost_usd = ( fresh_input       × input_rate_per_M
           + cache_read_tokens × cache_read_rate_per_M
           + cache_write_tokens× cache_write_rate_per_M
           + output_tokens     × output_rate_per_M ) / 1,000,000
```

With both cache counts at 0 this reduces exactly to the current two-term formula
(SC-003/SC-004 back-compat).

## Model Price (extended)

One catalog row. Format v2 (research D2):

```text
model-id|input_per_M|output_per_M[|cache_read_per_M[|cache_write_per_M]]
```

| Field | Type | Required | Rules |
|---|---|---|---|
| `model-id` | string | yes | Unchanged. Tolerant matching ladder unchanged. |
| `input_per_M` | decimal ≥ 0 | yes | Unchanged. |
| `output_per_M` | decimal ≥ 0 | yes | Unchanged. |
| `cache_read_per_M` | decimal ≥ 0 | no | NEW. Malformed value ⇒ treated absent + stderr warning. |
| `cache_write_per_M` | decimal ≥ 0 | no | NEW. Same degradation. |

**Derivation defaults** (research D3) when a field is absent:

```text
cache_read_rate  = 0.10 × resolved_input_rate
cache_write_rate = 1.25 × resolved_input_rate
```

`resolved_input_rate` is the output of the full FR-004 ladder (config override →
catalog → blended → split default), so config overrides propagate into derived
cache rates coherently.

## Measured Usage Record (external, read-only)

Host-owned per-call usage row (first host: VS Code Copilot session store, `events`
table). Never written by this extension; consumed only by the AI agent at skill
level (FR-014).

| Store column | Verified semantics |
|---|---|
| `session_id` | Session UUID; equals basename of `VSCODE_TARGET_SESSION_LOG`. |
| `usage_model` | Canonical model id (e.g. `claude-fable-5`). Sessions interleave models. |
| `usage_input_tokens` | Per-call input total — **includes** cache reads (verified: 60,914 in / 60,448 cr / 466 fresh). |
| `usage_output_tokens` | Per-call output tokens. |
| `usage_cache_read_tokens` | Cache-read subset. May be NULL ⇒ 0. |
| `usage_cache_write_tokens` | Cache-write subset. Empty on verified host ⇒ 0. |
| `usage_cost` | **Unpopulated — must not be used** (verified). |
| `timestamp` | Call time; drives Step Window scoping. |

**Known limitation (verified)**: in-flight sessions are not indexed (even after
reindex); only closed/reloaded sessions are visible. Absence ⇒ fallback, silently.

## Step Window

The time span whose usage is attributed to one workflow step. Not persisted —
computed by the agent at acquisition time.

| Bound | Rule |
|---|---|
| Lower | `ts` of the most recent Cost Entry for the **current spec** in the ledger; if none exists, unbounded (session start effectively bounds it). |
| Upper | Hook fire time (query time). |
| Scope | Always intersected with `session_id = current session` and `usage_model = active model`. |

**Anti-double-count invariant** (FR-011): consecutive steps in one session partition
the session's usage rows — each row is summed into at most one Cost Entry, because
each recorded entry's `ts` becomes the next step's lower bound.

**Fallback triggers** (any ⇒ skip measured mode): store tool unavailable; session id
unresolvable; ledger unreadable while entries exist for the spec; query error; zero
rows (or zero total) for the active model in the window.

## State transitions

None. The ledger is append-only (§IV); catalog and config are read-only inputs;
the store is an external read-only source.
