# spec-kit-cost

A [spec-kit](https://github.com/github/spec-kit) extension that tracks estimated
LLM token cost per workflow step, appends an append-only USD ledger, and reports
a cumulative per-spec breakdown.

## Features

- 💰 **Per-step inline summary** after each of 7 spec-kit lifecycle events
- 📊 **Cumulative report** automatically shown after `implement`, or on demand
- 🔒 **Append-only ledger** — entries are never modified, only appended
- 🔌 **Zero-config** — works out of the box with sensible defaults
- 🛠 **Pluggable providers** — `self-report` (default), `manual`, `log-file` (v1.1)
- 🎯 **Measured token usage** — on hosts with a session-store query tool (VS Code
  Copilot today), records real token/cache counts instead of estimates
- 💾 **Cache-aware pricing** — prices cache-read/cache-write tokens at their own
  rates instead of the full input rate
- 🐚 **Shell-first** — pure POSIX bash, no runtime dependencies

## Installation

```bash
# From the community catalog (once listed):
specify extension add cost

# Direct install from GitHub release:
specify extension add cost \
  --from https://github.com/rnoap/spec-kit-cost/archive/refs/tags/v1.0.0.zip
```

Requires spec-kit `>= 0.4.0`.

## AI Assistant Setup

When an AI coding assistant executes spec-kit commands, it must **run** the hook
scripts — not just list them. Some assistants (GitHub Copilot, Cursor, older Wibey
versions) need an explicit instruction to do this.

Add the following block to your project's `AGENTS.md` (or equivalent AI context file,
e.g. `.cursorrules`, GitHub Copilot instructions):

```markdown
### spec-kit cost hooks — execute mandatory hooks

When a spec-kit skill finishes and lists `after_*` hooks, any hook with `optional: false`
MUST be executed directly. `EXECUTE_COMMAND: <command>` is a GUI signal; in AI-agent mode
the AI model is the executor.

For `speckit.cost.record` (always `optional: false`), run:

    bash .specify/extensions/cost/scripts/bash/record-cost.sh \
      --step <event_name> \
      --model <MODEL_ID> \
      --in-chars <IN_CHARS> \
      --out-chars <OUT_CHARS>

where `<IN_CHARS>` and `<OUT_CHARS>` are **character counts** of the step's input and
output content. The script applies the `chars ÷ 4` heuristic internally.
After execution, relay the 💰 summary line verbatim in your response text.

> ⚠️ Never pass character counts into `--in-tokens`/`--out-tokens` — those flags bypass
> the ÷4 heuristic and inflate estimates by ~4×. Use `--in-tokens`/`--out-tokens` only
> when you have real token counts (e.g. `--provider manual` with dashboard values).
```

## Quick Start (Zero-Config)

Install the extension and run any spec-kit workflow step. After each step you'll
see a one-line cost summary:

```
💰 specify: ~1200 in / ~800 out tokens ≈ $0.0060
```

After the `implement` step, a full breakdown is shown automatically:

```
## Cost Report: 001-my-feature

| Step       | Input tokens | Output tokens | Cost (USD) |
|------------|-------------:|--------------:|-----------:|
| specify    |         1200 |           800 |    $0.0060 |
| clarify    |          900 |           500 |    $0.0042 |
| plan       |         2100 |          1400 |    $0.0105 |
| tasks      |          800 |           600 |    $0.0042 |
| implement  |         3500 |          2200 |    $0.0171 |

**Total: $0.0420** (5 step(s))
```

On hosts where real usage is available (see [Measured Token Usage](#measured-token-usage-v14)),
summaries and reports show cache-read/cache-write breakdowns and a source marker:

```
💰 plan: ~4228197 in (4010305 cached) / ~49756 out tokens ≈ $2.6031 [measured]
```

## Commands

| Command | Description |
|---------|-------------|
| `speckit.cost.record` | Record cost for the just-completed step (invoked by hooks) |
| `speckit.cost.report` | Show per-step breakdown + cumulative total for current spec |
| `speckit.cost.reset`  | Clear cost entries for current spec (requires confirmation) |

## Configuration

Create `.specify/extensions/cost/cost-config.yml` to customize:

```yaml
# Provider for token count collection.
# self-report (default) — AI estimates using chars ÷ 4 heuristic
# manual                — You supply token counts when prompted
# log-file              — Parse provider usage log (planned for v1.1)
provider: self-report

# Legacy blended USD cost per 1,000 tokens (applies to BOTH input and output).
# Leave unset to use per-model catalog rates, with split defaults
# ($3/M input, $15/M output) for models missing from the catalog.
# price_per_1k: 0.003

# Model label stored in ledger entries (fallback only — the active model is
# auto-detected from the host agent and matched against model-catalog.txt).
model: claude-sonnet-4
```

You can also override the provider for a single invocation:

```bash
export SPECKIT_COST_PROVIDER=manual
```

## Default Values

| Setting | Default | Notes |
|---------|---------|-------|
| `provider` | `self-report` | `chars ÷ 4` token heuristic |
| `price_per_1k` | _unset_ | Legacy blended rate; only used if explicitly set |
| Fallback rates | `$3/M` in, `$15/M` out | Used when the model is not in the catalog |
| `model` | `unknown` | Label fallback; the active model is auto-detected |

## Providers

### `self-report` (default)

The AI agent estimates token counts using the industry-standard `chars ÷ 4`
heuristic applied to the visible input and output content of each step. Results
are best-effort estimates within ~10% of actual billing counts for English prose.
No external data source required.

### `manual`

After each step, you are prompted to supply the exact input and output token
counts (e.g., from your provider's usage dashboard). Use this for billing-grade
accuracy.

### `log-file` (planned for v1.1)

Parse a provider-specific usage log file to extract exact token counts. In v1.0.0
this provider emits a non-blocking warning and skips the entry.

## Measured Token Usage (v1.4)

When `provider` is `self-report` (the default), the AI agent follows a three-rung
degradation ladder, always preferring the most accurate source available and
falling back silently — never blocking or warning the developer — when a rung is
unavailable:

1. **Measured session-store usage** — if the host exposes a session-store query
   tool, the agent aggregates real input/output/cache token counts for the
   current step directly from the store and records with `source: measured`.
2. **Host-reported usage totals** — a usage/billing panel, session token counter,
   or API usage metadata exposed by the host agent.
3. **`chars ÷ 4` heuristic** — always available; the original v1.0.0 behavior.

### Host compatibility

| Host | Rung 1 (measured) | Rung 2/3 (fallback) |
|------|:---:|:---:|
| GitHub Copilot (VS Code) | ✅ session-store SQL tool | ✅ |
| Wibey | — | ✅ |
| Cursor | — | ✅ |
| Claude Code | — | ✅ |
| Other agents | — | ✅ |

On hosts without a session-store query tool, behavior and output are **byte-identical**
to v1.3.0 — this feature only adds capability, it never changes existing behavior.

### Known limitation

In-flight (currently open) sessions are not indexed by the store even after a
reindex — only closed or resumed sessions have queryable usage data. Measured mode
therefore commonly falls back to Rung 2/3 during a live session and succeeds once
the session has been closed and reopened. This is expected and never surfaced as
an error.

## Cache-Aware Pricing (v1.4)

Many providers charge separately for **cache-read** and **cache-write** tokens at
rates lower/higher than fresh input tokens. `model-catalog.txt` supports two
optional trailing columns for these rates:

```
# model-id|input_per_M_USD|output_per_M_USD[|cache_read_per_M_USD[|cache_write_per_M_USD]]
claude-sonnet-4-6|3|15|0.3|3.75
```

When a model omits the cache columns, rates are derived from its input rate:
**cache-read = 0.10×** input rate, **cache-write = 1.25×** input rate. Cost is
computed as:

$$
\text{cost} = \frac{\text{fresh\_in} \times r_{in} + \text{cache\_read} \times r_{cr} + \text{cache\_write} \times r_{cw} + \text{output} \times r_{out}}{10^6}
$$

where `fresh_in = max(0, input_tokens − cache_read_tokens − cache_write_tokens)`.
Entries with no cache tokens price identically to v1.3.0.

To record cache token counts manually (e.g. from a provider dashboard):

```bash
bash scripts/bash/record-cost.sh \
  --step after_plan --model claude-sonnet-4-6 \
  --in-tokens 4228197 --out-tokens 49756 \
  --cache-read-tokens 4010305 --source measured
```

## Ledger Format

Cost entries are stored as JSON Lines at `.specify/extensions/cost/cost-ledger.jsonl`.
Each line is one record:

```json
{
  "v": 1,
  "ts": "2026-07-13T12:00:00Z",
  "step": "after_specify",
  "spec": "001-my-feature",
  "provider": "self-report",
  "source": "measured",
  "input_tokens": 1200,
  "output_tokens": 800,
  "cache_read_tokens": 400,
  "cache_write_tokens": 0,
  "model": "claude-sonnet-4",
  "cost_usd": 0.006000,
  "note": ""
}
```

`source`, `cache_read_tokens`, and `cache_write_tokens` are **optional, additive**
fields (v1.4): `source` is emitted only when `"measured"`; the cache fields are
emitted only when greater than 0. Legacy entries and readers are unaffected.

The ledger is **append-only** — entries are never modified or deleted by normal
operation. Use `speckit.cost.reset` to clear entries for a specific spec.

## Troubleshooting

**Hooks don't seem to run / no 💰 summary appears after a step**
Some AI assistants list `after_*` hooks without executing them. Make sure your
project's `AGENTS.md` (or equivalent) contains the block from
[AI Assistant Setup](#ai-assistant-setup) instructing the model to run
`speckit.cost.record` directly whenever it sees a hook marked `optional: false`.

**Cost always uses the $3/M in, $15/M out fallback rate**
This means the active model label didn't resolve against `model-catalog.txt`.
Check that:
- The model is actually listed in `model-catalog.txt` (or add it — no script
  changes needed).
- The label isn't an unusual alias; tolerant matching handles case, spaces,
  dots, and dated suffixes (e.g. `claude-sonnet-4-6-20260101`), but very custom
  names may still miss.
- You aren't overriding it unintentionally via `input_rate_per_1k` /
  `output_rate_per_1k` in `cost-config.yml`.

**`⚠ Configuration may be required` after installing**
This is expected and non-blocking — it just means `cost-config.yml` hasn't been
created yet. The extension works zero-config with sensible defaults; create
`.specify/extensions/cost/cost-config.yml` only if you want to customize
provider/pricing (see [Configuration](#configuration)).

**`speckit.cost.report` shows no entries / an empty table**
- Confirm you're running it from within the spec whose cost you want to see —
  the current spec is detected from `.specify/feature.json` or the active
  branch name.
- Confirm at least one `speckit.cost.record` call has succeeded for that spec
  (check `.specify/extensions/cost/cost-ledger.jsonl` for lines with a matching
  `"spec"` field).

**`Permission denied` running the scripts directly**
Invoke them via `bash`, e.g. `bash scripts/bash/record-cost.sh ...`, rather than
executing them directly — this sidesteps the executable bit entirely and works
identically on every platform.

**bats tests fail only on Windows with emoji-related assertion errors**
A handful of `tests/bats` assertions anchor on the 💰 emoji using
`grep -qE '^💰...'`; in some Git Bash locales on Windows this fails to match
even though the script's byte output is correct. This is a known, pre-existing
locale quirk — not a functional regression — and doesn't affect real usage.

If you hit something not covered here, please
[open an issue](https://github.com/rnoap/spec-kit-cost/issues).

## Contributing

Contributions are welcome! This extension is pure POSIX bash with **no runtime
dependencies** — please keep it that way when submitting changes.

1. **Dev-install loop**: after editing files at the repo root, reinstall the
   local copy into a spec-kit project with
   `specify extension add . --dev --force` (this regenerates the installed
   copy under `.specify/extensions/cost/` — never hand-edit that directory).
2. **Run the tests** with [bats-core](https://github.com/bats-core/bats-core)
   before opening a PR:
   ```bash
   bats tests/bats/              # all suites
   bats tests/bats/record.bats   # single suite
   ```
3. **Follow Spec-Driven Development**: new features go through
   `specs/<NNN>-<name>/` (spec → plan → tasks) — see the existing folders under
   [`specs/`](specs/) for examples.
4. **Update `CHANGELOG.md`** (Keep a Changelog format) and bump `version` in
   `extension.yml` for any user-visible change.
5. Open a pull request describing the change and referencing the relevant spec,
   if any.

For bugs, questions, or feature requests, please use
[GitHub Issues](https://github.com/rnoap/spec-kit-cost/issues).

## License

MIT — see [LICENSE](LICENSE).

## Community Catalog

You can find us at [speckit-community.github.io/extensions](https://speckit-community.github.io/extensions).
The exact URL to this plugin's listing will be added here soon.
