# Contract: Model Price Catalog Format

**File**: `.specify/extensions/cost/model-catalog.txt`
**Version**: 1
**Encoding**: UTF-8, LF line endings

---

## Format

One entry per line. Three pipe-separated fields:

```
<model-id>|<input_per_M>|<output_per_M>
```

### Rules

1. Lines starting with `#` (after optional leading whitespace) are comments — ignored.
2. Blank lines are ignored.
3. Fields are separated by exactly one `|` character.
4. `model-id` must not contain `|` or whitespace.
5. `input_per_M` and `output_per_M` are non-negative decimal numbers (e.g., `3`, `0.75`, `1.25`).
6. On duplicate model IDs, the **first** matching line wins.
7. Lines with fewer than 3 fields, non-numeric rate fields, or empty model IDs are skipped with a warning to stderr.

### Example

```
# spec-kit-cost model price catalog
# Format: model-id|input_per_M_USD|output_per_M_USD
# Source (Claude): wibey-cli src/constants/models.ts
# Source (OpenAI): openai.com/api/pricing (verified 2026-07-13)

# Claude models (Wibey gateway rates — differ from public Anthropic list prices)
claude-opus-4-8|5|25
claude-opus-4-6|5|25
claude-sonnet-5|3|15
claude-sonnet-4-6|3|15
claude-sonnet-4-5-20250929|3|15
claude-sonnet-4-20250514|3|15
claude-haiku-4-5-20251001|1|5

# OpenAI models (public API rates — not auto-detected via Wibey gateway)
gpt-5.6-sol|5|30
gpt-5.6-terra|2.5|15
gpt-5.6-luna|1|6
gpt-5.5|5|30
gpt-5.4|2.5|15
gpt-5.4-mini|0.75|4.5
gpt-5.4-nano|0.2|1.25
```

---

## Lookup Algorithm

> **Amended 2026-07-16 (v1.3.0)** — the original exact-match `grep` lookup was replaced
> by tolerant resolution. See [specs/003-tolerant-model-matching/spec.md](../../003-tolerant-model-matching/spec.md).

`catalog_get_rates <model_label>` first resolves the label via `catalog_resolve_model`,
then returns `input_per_M|output_per_M` for the resolved ID (empty string if unresolved).
Parsing uses `awk` field comparison (`$1 == id`) — no regex interpretation of the input.

### Matching ladder (first hit wins)

1. **Exact** — the label matches a catalog ID verbatim.
2. **Normalized** — lowercase, trimmed, trailing parenthetical stripped
   (`GPT-5.3-Codex (Preview)` → `gpt-5.3-codex`), spaces/underscores → dashes,
   repeated dashes collapsed.
3. **Dots → dashes** — normalized form with `.` replaced by `-`
   (`claude-sonnet-4.6` → `claude-sonnet-4-6`).
4. **Longest dash-boundary prefix** — the longest catalog ID that is a prefix of the
   candidate ending at a dash boundary (`claude-opus-4-8-20260220` → `claude-opus-4-8`;
   `gpt-5.4-mini-2026-01-01` matches `gpt-5.4-mini`, not `gpt-5.4`).

Comments and blank lines are stripped and fields trimmed before comparison. Duplicate
IDs: first line wins (rule 6). The same ladder is applied by `record-cost.sh` (which
stores the resolved canonical ID in the ledger) and by `report-cost.sh` when repricing.

---

## Update Procedure

1. Open `model-catalog.txt`.
2. Add a line per new model: `new-model-id|input_per_M|output_per_M`.
3. Add a comment with the price source and verification date.
4. No script changes are required.

Catalog updates are independent of shell script changes. The catalog version is not formally tracked; the git history of `model-catalog.txt` is the version record.
