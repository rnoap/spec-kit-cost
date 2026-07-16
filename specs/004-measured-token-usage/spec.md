# Feature Specification: Measured Token Usage and Cache-Aware Cost Pricing

**Feature Branch**: `004-measured-token-usage`

**Created**: 2026-07-16

**Status**: Draft

**Input**: User description: "con todo lo que acabamos de revisar en el plan para mejora aún mas la precisión del calculo de costo, y tener en cuenta mantener compatibilidad con otros asistentes de codigo donde puede que no estén disponibles estas opciones para alimentar el calculo de costo. también incuye las Further Considerations de una en este nuevo spec" — building on the reviewed proposal: feed the cost ledger with real measured token usage from the host's session records instead of the character-count heuristic, with full cache-aware pricing fidelity, while preserving identical behavior on assistants that cannot provide measured usage.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Cache-Aware Pricing for Exact Token Counts (Priority: P1)

A developer supplies exact token counts to the cost recorder — from manual entry, a
host usage panel, or an automated feed. In long agentic sessions the input side is
dominated by prompt-cache reads: in a verified real session, 4.01M of 4.23M input
tokens were cache reads. Providers bill cache reads at a small fraction of the fresh
input rate, so pricing every input token at the full rate would price the step's
input side at ≈ $12.68 when its true cache-aware cost is ≈ $1.86 — a 6.8×
overstatement (full recorded entry: ≈ $13.43 naive vs ≈ $2.60 correct). The extension
must price fresh input, cache reads, cache writes, and output each at their own rate,
so that exact token counts produce exact costs.

**Why this priority**: Without cache-aware pricing, feeding measured counts into the
recorder produces results *worse* than the current estimation heuristic. This story is
the foundation that makes every other accuracy improvement viable, and it independently
benefits developers who already supply exact counts today.

**Independent Test**: Record an entry with explicit fresh-input, cache-read,
cache-write, and output token counts for a model with known rates. Verify the recorded
cost matches the hand-computed four-term formula to four decimal places.

**Acceptance Scenarios**:

1. **Given** a model whose price catalog entry includes cache-read and cache-write
   rates, **When** an entry is recorded with separated token counts, **Then** the cost
   equals `(fresh_input × input_rate) + (cache_read × cache_read_rate) +
   (cache_write × cache_write_rate) + (output × output_rate)`.
2. **Given** a model whose catalog entry has no cache rates, **When** an entry is
   recorded with cache token counts, **Then** default cache rates derived from the
   model's input rate (10% for reads, 125% for writes) are applied and the entry is
   recorded without error.
3. **Given** an entry recorded with no cache token counts (today's call shape),
   **When** the cost is computed, **Then** the formula, ledger record, and inline
   summary are identical to the previous release.
4. **Given** a ledger containing a mix of pre-feature entries (no cache fields) and
   new entries (with cache fields), **When** the cost report runs, **Then** totals are
   correct, treating absent cache counts as zero.

---

### User Story 2 - Measured Usage from the Host's Session Records (Priority: P2)

A developer works on a host assistant that keeps per-call usage records for the
current session (e.g., VS Code Copilot's session store, which records exact input,
output, and cached token counts per model call). When a workflow step completes, the
recording flow retrieves the measured usage for the current session — scoped to the
active model and to the time window since the previous recorded step — separates
cached from fresh input tokens, and records **measured** counts instead of estimated
ones. The ledger transitions from "estimated" to "measured" wherever the data exists.

**Why this priority**: This is the headline value of the feature — replacing a ±25%
(or worse) character heuristic with exact provider-reported numbers. It depends on
User Story 1 for correct pricing, which is why it is P2.

**Independent Test**: On a host exposing session usage records, complete one workflow
step. Compare the recorded input/output/cache counts against the host's own per-call
records summed over the step window — they must match exactly.

**Acceptance Scenarios**:

1. **Given** usage records are available for the current session, **When** the
   recording hook fires, **Then** the recorded token counts equal the sum of the
   host's per-call records for the active model within the step window.
2. **Given** a previous ledger entry exists for the current spec, **When** the next
   step is recorded, **Then** only usage newer than that previous entry is summed, so
   consecutive steps never double-count the same calls.
3. **Given** the session interleaves calls from other models (e.g., an auxiliary
   utility model used by the host), **When** usage is summed, **Then** other-model
   calls are excluded from the recorded counts and their presence is mentioned in the
   entry's note.
4. **Given** an entry was produced from measured usage, **Then** the entry is marked
   as measured, distinguishable from estimated entries when reviewing the ledger or
   report.
5. **Given** the usage query returns no rows for the active model (or a zero total),
   **When** the hook fires, **Then** the flow falls back to estimation exactly as if
   no usage records existed.

---

### User Story 3 - Unchanged Experience on Hosts Without Usage Records (Priority: P3)

A developer uses the extension on an assistant that has no queryable usage records
(e.g., Wibey, Cursor, Claude Code today). Every workflow step records costs exactly
as it does in the current release: the character-count estimation path, the same
inline summary, the same warnings — no new errors, prompts, or noise. Installing this
feature must never degrade or change behavior for these developers.

**Why this priority**: Explicit compatibility requirement from the feature request.
It protects the extension's core promise — it works with zero configuration on any
AI coding assistant — but it describes preserved behavior rather than new value.

**Independent Test**: On a host without measured-usage capability, record a step and
compare the full observable behavior (ledger record shape, summary line, warnings)
against the previous release — they must be indistinguishable.

**Acceptance Scenarios**:

1. **Given** the host offers no measured-usage capability, **When** a step completes,
   **Then** the character-based estimation path is used and the output format is
   unchanged from the previous release.
2. **Given** measured-usage retrieval starts but fails (error, timeout, missing
   data), **When** the hook fires, **Then** recording proceeds through the fallback
   without blocking the workflow, and at most a non-fatal warning is emitted.
3. **Given** the current session's records are not yet visible in the host's store
   (a verified limitation for in-flight sessions), **When** the hook fires, **Then**
   the fallback applies silently.

---

### Edge Cases

- **Cache count anomaly**: if the reported cache-read count exceeds the measured input
  total, the derived fresh-input count floors at zero (never negative) and the entry
  notes the anomaly.
- **First step of a spec**: no previous ledger entry exists — the step window starts
  at the beginning of the current session.
- **Concurrent sessions in the same repository**: only the current session's records
  may be summed; if the current session cannot be identified unambiguously, the flow
  falls back to estimation rather than guessing.
- **Model label mismatch**: the host's usage records may label the model differently
  than the detected active model (e.g., a dated variant). The existing tolerant
  matching rules decide equivalence; if unresolvable, fall back and note it.
- **Only auxiliary-model usage in the window**: if the active model has no usage rows
  but other models do, fall back to estimation for the active model.
- **Hosts that never report cache writes**: absent write counts are simply recorded
  as zero — no warning.
- **Ledger read failure during window scoping**: if the previous entry's timestamp
  cannot be determined, fall back to estimation rather than risking double-counting.

## Requirements *(mandatory)*

### Functional Requirements

**Pricing engine (cache-aware)**

- **FR-001**: The model price catalog MUST support optional per-model cache-read and
  cache-write rates in addition to the existing input and output rates. Catalog
  entries without cache rates MUST remain valid and behave as they do today.
- **FR-002**: When a model has no cache rates in the catalog, the system MUST derive
  defaults from that model's input rate: cache-read = 10% of the input rate,
  cache-write = 125% of the input rate.
- **FR-003**: Cost MUST be computed as the sum of four independently priced terms:
  fresh input, cache reads, cache writes, and output. When cache counts are zero or
  absent, the result MUST equal the current two-term computation exactly.
- **FR-004**: The recording interface MUST accept optional cache-read and cache-write
  token counts alongside the existing input and output counts.

**Ledger and reporting**

- **FR-005**: Ledger entries MUST persist cache token counts when they were provided.
  Entries without cache counts (including all pre-feature entries) MUST remain valid
  and be interpreted as zero cache usage.
- **FR-006**: The cost report MUST aggregate ledgers containing a mix of entries with
  and without cache counts, producing correct per-step and cumulative totals.
- **FR-007**: The inline summary MUST disclose the cached portion of input whenever a
  non-zero cache count was recorded, so developers can see why the cost is lower than
  a naive full-rate reading would suggest.
- **FR-008**: Each ledger entry MUST record whether its token counts were measured
  (from host usage records) or estimated (character heuristic or self-report), so
  reports can distinguish accuracy levels.

**Measured usage acquisition**

- **FR-009**: When the host assistant exposes per-call usage records for the current
  session, the recording flow MUST prefer those measured counts over character-based
  estimation.
- **FR-010**: Measured input totals that include cached tokens MUST be separated
  before pricing: fresh input = measured input total minus cached tokens, floored at
  zero.
- **FR-011**: Measured sums MUST be scoped to the current step's window — usage
  recorded after the previous ledger entry for the same spec (or after session start
  when no previous entry exists) — so that consecutive steps never double-count.
- **FR-012**: Usage attributed to models other than the active model MUST be excluded
  from the recorded counts; when such usage exists in the window, its presence MUST be
  mentioned in the entry's note.

**Compatibility and degradation**

- **FR-013**: The recording flow MUST degrade gracefully through this ladder:
  measured session usage → host-reported usage totals → character-count estimation.
  Absence or failure of any rung MUST NOT block the workflow, emit fatal errors, or
  change the behavior of the remaining rungs.
- **FR-014**: The persistence layer MUST NOT acquire new runtime dependencies to
  support measured usage. Retrieval of measured usage is performed by the AI agent at
  workflow level, which passes explicit counts to the recording interface.

### Key Entities

- **Cost Entry**: one recorded workflow step. Extended with: cache-read token count,
  cache-write token count (both optional, absent = zero), and a source marker
  (measured vs estimated). All existing fields keep their current meaning.
- **Model Price**: per-model rate card. Extended with optional cache-read and
  cache-write rates; when absent, defaults derive from the input rate (FR-002).
- **Measured Usage Record**: an external, host-owned record of a single model call —
  model identifier, input tokens (inclusive of cached tokens), output tokens,
  cache-read tokens, cache-write tokens, and a timestamp. Read-only to this extension.
- **Step Window**: the time span attributed to one workflow step — from the previous
  Cost Entry for the same spec (or session start) to the moment the recording hook
  fires.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a host exposing per-call usage records, the token counts recorded
  for a completed step match the host's own records for that window exactly (0%
  deviation), replacing the ±25%-or-worse character heuristic.
- **SC-002**: For a step in which at least 90% of input tokens are cache reads on a
  premium model, the recorded cost is within 10% of the true provider-billed cost.
  Reference case (verified real session): 4,228,197 input / 4,010,305 cached /
  49,756 output on a $3-input / $15-output model must record ≈ $2.60 total (input
  side ≈ $1.86), not the ≈ $13.43 a naive full-rate computation would produce
  ($12.68 of it on the input side).
- **SC-003**: On hosts without measured-usage capability, observable recording
  behavior is unchanged from the previous release — same ledger record shape, same
  summary format, no new warnings — and the entire pre-existing automated test suite
  passes without modification.
- **SC-004**: Cost reports over ledgers created before this feature produce the same
  totals for those entries as the previous release (bit-for-bit compatible pricing of
  legacy entries).
- **SC-005**: A price catalog written in the pre-feature format (no cache rate
  fields) continues to resolve every model to the same rates as before.
- **SC-006**: 100% of recording attempts complete without blocking the workflow,
  including when measured-usage retrieval fails at any point mid-flow.

## Out of Scope

- Implementing the `log-file` provider (still a stub; unrelated to this feature).
- Retroactive repricing or mutation of historical ledger entries.
- Querying host usage records from the persistence layer itself (shell scripts) —
  acquisition is an agent-level concern (FR-014).
- Cost tracking for non-text modalities (images, audio).
- Real-time (mid-step) cost display; recording remains a post-step hook.

## Assumptions

- **Verified**: on the first supported host, measured input totals *include*
  cache-read tokens; separation (FR-010) is mandatory for correct pricing.
- **Verified**: records for an in-flight session may be unavailable until the session
  closes; measured mode is therefore best-effort and the estimation fallback remains
  a permanent, first-class path (User Story 3).
- **Verified**: the host's own per-call cost field is unpopulated and cannot be used;
  the extension always prices from token counts and its own rate resolution.
- **Verified**: sessions interleave calls from multiple models (auxiliary utility
  models alongside the primary one); active-model filtering (FR-012) is required for
  honest attribution.
- The 10% read / 125% write default cache-rate derivation reflects the dominant
  provider's published cache billing; per-model catalog values override it (FR-001),
  and models never exercising cache writes simply record zero write counts.
- Measured-usage capability currently exists on VS Code Copilot (session store).
  Wibey, Cursor, and Claude Code currently offer none; they remain on the estimation
  path with unchanged behavior.
- The ledger schema remains at its current version with additive optional fields;
  absent fields mean zero. Existing field semantics do not change, so no schema
  version bump is required.
- Cache-read and cache-write rates, like all catalog rates, are standard-tier USD
  per million tokens.
