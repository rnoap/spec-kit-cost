# Contract: Commands and Script CLIs

**Feature**: `001-cost-tracking-per-step`

Defines the interface of each command (`.md` AI instruction file) and the bash script it
delegates to. Per Constitution §V, the `.md` files contain AI-executed instructions only;
all persistent I/O and math live in `scripts/bash/`.

**Division of labor**: The AI command file gathers content-derived inputs (e.g., estimated
input/output content for `self-report`) and invokes the script. The script performs
provider resolution, `chars ÷ 4` estimation, cost math, JSONL persistence, and rendering.

---

## C1 — `speckit.cost.record` (hook-invoked; also usable manually)

**Purpose**: Record one Cost Entry for the just-completed step and print the inline
summary. Wired to all seven `after_*` events.

**Command `.md` responsibilities**:

- Determine the current step name from the firing hook event (`after_<step>`).
- For `self-report`: estimate the character size of the step's input content and output
  content visible to the agent, and pass those to the script.
- Invoke: `bash scripts/bash/record-cost.sh --step <after_step> [--in-chars N] [--out-chars N] [--provider P] [--count N] [--note "..."]`

**Script `record-cost.sh` interface**:

| Argument | Meaning |
|----------|---------|
| `--step <after_step>` | Required. One of the seven `after_*` event names. |
| `--in-chars N` / `--out-chars N` | Input/output content char counts (self-report). Script computes tokens = `ceil(N/4)`. |
| `--in-tokens N` / `--out-tokens N` | Direct token counts (used by `manual`/`log-file` paths). |
| `--provider P` | Override provider for this invocation (highest precedence). |
| `--note "..."` | Optional note stored in the entry. |

**Behavior**:

- **CR-R1**: Resolve provider by precedence: `--provider` → `SPECKIT_COST_PROVIDER` →
  config `provider` → `self-report` (§III, FR-012).
- **CR-R2**: Resolve `price_per_1k` (default `0.003`) and `model` (default `unknown`)
  from config (FR-011, FR-014).
- **CR-R3**: Read `spec` from `.specify/feature.json` (feature dir name) (FR-004).
- **CR-R4**: Compute `cost_usd = (input_tokens + output_tokens)/1000 * price_per_1k` via
  `awk`, stored at 6dp (R2).
- **CR-R5**: Append exactly one valid JSONL record (schema v1, field order per
  data-model.md) to the ledger (FR-003, FR-018). `mkdir -p` the ledger dir first.
- **CR-R6**: Print exactly one inline summary line to stdout:
  `💰 <step>: ~<in> in / ~<out> out tokens ≈ $<cost>` where `<step>` has the `after_`
  prefix stripped and `<cost>` is 4dp (FR-002, SC-001).
- **CR-R7 (non-blocking)**: On any failure (missing estimate, unwritable ledger, config
  read error) print exactly one line to stderr —
  `⚠️  speckit-cost: <reason> — entry skipped` — write **no** ledger entry, and
  `exit 0` (FR-015, SC-007, Constitution §II).
- **CR-R8 (write isolation)**: Writes only under `.specify/extensions/cost/`. Never runs
  `git`, `rm` outside that dir, or edits spec/source files (Constitution §II, FR-016).

**Exit code**: Always `0` (hook must never block the workflow).

---

## C2 — `speckit.cost.report` (read-only; on-demand and auto after implement)

**Purpose**: Consolidate all entries for the current spec into a per-step breakdown table
plus cumulative USD total.

**Command `.md` responsibilities**: Invoke `bash scripts/bash/report-cost.sh` and present
its output. No content estimation needed.

**Script `report-cost.sh` interface**:

| Argument | Meaning |
|----------|---------|
| `--spec <id>` | Optional. Defaults to the current feature dir name from `.specify/feature.json`. |

**Behavior**:

- **CR-P1**: Read `spec` from `.specify/feature.json` unless `--spec` given (FR-004).
- **CR-P2**: Filter ledger to entries whose `spec` matches; include **zero** entries from
  other specs (FR-005, SC-004).
- **CR-P3**: Render a breakdown table: one row per entry (step, input_tokens,
  output_tokens, per-step cost at 4dp), then a cumulative total row in USD (FR-005).
- **CR-P4**: Cumulative total equals the sum of per-step `cost_usd` for the spec, summed
  from 6dp stored values (SC-003).
- **CR-P5 (read-only)**: MUST NOT write to the ledger under any circumstance (FR-010,
  Constitution §IV).
- **CR-P6 (empty state)**: When the spec has no entries, print the explicit message
  `No cost data recorded for this spec.` and exit `0` — never an empty table or error
  (FR-017, SC-008).
- **CR-P7**: Runnable at any time, independent of any hook (FR-006).

**Exit code**: `0` on success and on empty-state.

---

## C3 — `speckit.cost.reset` (confirmation-gated mutation)

**Purpose**: Clear recorded entries for the current spec.

**Command `.md` responsibilities**: Prompt the developer for explicit confirmation, then
invoke the script only if confirmed.

**Script `reset-cost.sh` interface**:

| Argument | Meaning |
|----------|---------|
| `--spec <id>` | Optional. Defaults to current feature dir name. |
| `--yes` | Required to actually delete; absent → the script refuses and prints how to confirm. |

**Behavior**:

- **CR-X1**: Without `--yes`, the script makes **no** change and reports that confirmation
  is required (FR-009, SC-006). The AI command file is responsible for obtaining explicit
  human confirmation before passing `--yes`.
- **CR-X2 (scope — explicit decision)**: Reset removes only the **current spec's** entries
  (per-spec), preserving other specs' lines. Rewrite is done via temp file + atomic `mv`
  (R4). This is the plain reading of US3 ("for that spec / spec session"); the
  constitution permits reset as the one command that removes entries.
- **CR-X3**: After a confirmed reset, a subsequent `speckit.cost.report` for the spec
  reports the empty state (FR-008, SC-006/CR-P6).
- **CR-X4 (write isolation)**: Operates only on the ledger under
  `.specify/extensions/cost/` (Constitution §II).

**Exit code**: `0` on success or on declined/unconfirmed reset.

---

## Cross-cutting contract invariants

| ID | Invariant | Source |
|----|-----------|--------|
| CR-G1 | No command writes outside `.specify/extensions/cost/`. | Constitution §II, FR-016 |
| CR-G2 | `record` and hook scripts exit `0` even on failure. | Constitution §II, FR-015 |
| CR-G3 | Only `reset` may remove ledger entries, and only after `--yes`. | Constitution §IV, FR-009 |
| CR-G4 | `report` never writes. | Constitution §IV, FR-010 |
| CR-G5 | All scripts are POSIX bash; no jq/python/node at runtime. | Constitution §V |
