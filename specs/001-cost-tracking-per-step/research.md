# Phase 0 Research: Cost Tracking Per Workflow Step

**Feature**: `001-cost-tracking-per-step` | **Date**: 2026-07-13

**Purpose**: Resolve the technical unknowns implied by Principle V (Shell-First, Zero
Runtime Dependencies). Every decision below is constrained to POSIX-compatible Bash plus
standard POSIX utilities (`awk`, `sed`, `grep`, `date`, `printf`, `mktemp`, `mv`). No
`jq`, Python, or Node.js is permitted at runtime.

---

## R1 — Emit and parse JSON Lines without `jq`

**Decision**: Emit each ledger record as a single JSON object per line using `printf`
with pre-escaped string values. Parse by matching one field at a time with `grep`/`sed`
per line, treating the file as line-oriented text (one self-contained JSON object per
line).

**Rationale**:

- The record schema (Constitution §IV) is flat — no nested objects or arrays — so a
  single `printf` format string produces valid JSONL deterministically.
- Field values are controlled: timestamps, enum step names, numeric token counts, a
  model label, and a computed USD figure. Only `spec`, `model`, and `note` are free-text
  and require escaping (backslash and double-quote → `\\` and `\"`, done with `sed`).
- Reading is per-spec filtering plus numeric summation, both of which `awk` performs on a
  line-oriented file without needing a JSON parser: match `"spec":"<id>"` and extract
  `"cost_usd":<num>` / token fields with a field-scoped regex.

**Alternatives considered**:

- **`jq` for emit/parse** — rejected: violates Principle V (external runtime dependency).
- **CSV/TSV ledger** — rejected: the constitution fixes the format as JSON Lines at a
  fixed path; CSV would be a contract violation.
- **Full regex JSON parser in awk** — rejected as over-engineering: records are flat and
  self-emitted, so field-scoped extraction is sufficient and far simpler to audit.

**Escaping rule (record-write path)**: before interpolation, every free-text field is
passed through `sed 's/\\/\\\\/g; s/"/\\"/g'`. Newlines are not expected in these fields;
if present they are stripped (`tr -d '\n'`) so one record always occupies one line — the
invariant the reader relies on.

---

## R2 — Floating-point cost math in POSIX shell

**Decision**: Perform all cost arithmetic in `awk`, which provides IEEE-754 doubles and
`printf`-style formatting. Bash itself has no floating-point support, so no cost math is
done in pure bash.

**Formula**: `cost_usd = (input_tokens + output_tokens) / 1000 * price_per_1k`

**Rendering**:

- Ledger `cost_usd` field: formatted with `awk '{printf "%.6f", ...}'` (6 decimals) to
  preserve precision for later summation.
- Inline summary and report display: `printf "%.4f"` (4 decimals) per FR-002 / SC-001.

**Rationale**:

- `awk` is a standard POSIX utility (Principle V compliant) and is the canonical way to
  do float math in shell pipelines.
- Storing 6 decimals in the ledger but displaying 4 avoids compounding rounding error
  when the report sums many small per-step costs (SC-003 requires the cumulative total to
  equal the sum of per-step costs).

**Alternatives considered**:

- **`bc -l`** — rejected: `bc` is not guaranteed present on minimal systems (e.g., some
  Alpine/BusyBox images) whereas `awk` is part of the POSIX baseline; `awk` also handles
  both math and formatting in one pass.
- **Integer cents arithmetic in bash** — rejected: prices like `$0.003 / 1K` produce
  sub-cent per-step figures that integer cents cannot represent; would force a custom
  fixed-point scheme that is harder to audit than `awk` doubles.

---

## R3 — Read `cost-config.yml` without a YAML parser

**Decision**: Read the three known scalar keys (`provider`, `price_per_1k`, `model`) with
a small `grep`/`sed` "flat key: value" extractor. Treat the config as a flat map of
`key: value` pairs; ignore comments (`#`) and blank lines. Any key not found falls back
to its documented default.

**Extractor contract** (per key):

```
value=$(grep -E "^[[:space:]]*<key>[[:space:]]*:" "$CONFIG" 2>/dev/null \
        | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*#.*$//; s/^["'\'']//; s/["'\'']$//')
```

**Rationale**:

- The Cost Configuration entity has exactly three flat scalar attributes (FR-011,
  FR-012, and default model label) — no nesting, lists, or anchors — so a full YAML
  parser is unnecessary.
- Missing file or missing key both resolve to defaults, satisfying FR-014 (zero-config
  operation): `provider=self-report`, `price_per_1k=0.003`, `model=unknown`.
- `SPECKIT_COST_PROVIDER` (Constitution §III) and a per-invocation override take
  precedence over the file value in the resolution order below.

**Provider resolution order** (highest precedence first): runtime override argument →
`SPECKIT_COST_PROVIDER` env var → `cost-config.yml` value → default `self-report`.

**Alternatives considered**:

- **Bundle a YAML parser (e.g., `yq`)** — rejected: external runtime dependency
  (Principle V) and overkill for a three-key flat file.
- **Switch config to a `.env`/`KEY=VALUE` file** — rejected: the constitution fixes the
  config path and name as `cost-config.yml`; changing the format is a contract change.

---

## R4 — Atomic append and safe reset without corrupting the ledger

**Decision**: Append with a single `>>` redirection of one fully-formed line (append is
atomic for a single small write on POSIX filesystems). Reset rewrites the ledger through
a temp file + `mv` (atomic replace) so an interrupted reset never leaves a truncated
ledger.

**Rationale**:

- Principle IV forbids modifying or deleting existing lines during normal recording; a
  single `>>` of a complete line honors append-only.
- Reset is the one permitted mutation (Constitution §IV). Per-spec reset filters out the
  current spec's lines with `grep -v` / `awk` into a temp file, then `mv` over the
  original — atomic, and the original is intact until the final rename.
- FR-015 (never block the workflow): the record path traps errors and `exit 0`s after
  emitting exactly one stderr warning; a failed append writes nothing partial because the
  line is assembled fully before the single redirection.

**Alternatives considered**:

- **In-place `sed -i` for reset** — rejected: `sed -i` is non-portable (GNU vs BSD
  differ) and edits in place, risking corruption on interruption. Temp-file + `mv` is
  portable and atomic.

---

## R5 — Testing approach (dev-time only)

**Decision**: Use **`bats-core`** as the test harness, invoked only in development/CI.
This is a dev-time dependency, not a runtime dependency, so it does not violate
Principle V (which governs the shipped hook/command execution path).

**Rationale**:

- The persistent logic lives in bash scripts (Principle V); `bats-core` is the de-facto
  standard for testing bash and asserts on stdout/stderr/exit codes and file contents —
  exactly what these scripts produce.
- Runtime remains dependency-free: end users install the extension and run it with pure
  bash + POSIX utilities. `bats-core` is never invoked by hooks or commands.

**Alternatives considered**:

- **Plain `sh` assertion scripts** — viable and zero-dependency, but produces more
  boilerplate and weaker failure diagnostics; kept as a fallback if `bats-core` is
  unavailable in CI.
- **shUnit2** — comparable to bats; bats chosen for wider familiarity and clearer TAP
  output.

---

## Resolved unknowns summary

| Unknown | Resolution |
|---------|-----------|
| JSONL emit/parse without jq | `printf` emit + field-scoped `awk`/`grep`/`sed` parse (R1) |
| Float cost math in shell | `awk` doubles; store 6dp, display 4dp (R2) |
| YAML config without parser | flat `grep`/`sed` key extractor, defaults on miss (R3) |
| Atomic append / safe reset | single-line `>>` append; temp-file + `mv` reset (R4) |
| Testing | `bats-core` dev-time only; runtime stays dependency-free (R5) |

No `NEEDS CLARIFICATION` items remain.
