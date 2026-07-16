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
  "input_tokens": 1200,
  "output_tokens": 800,
  "model": "claude-sonnet-4",
  "cost_usd": 0.006000,
  "note": ""
}
```

The ledger is **append-only** — entries are never modified or deleted by normal
operation. Use `speckit.cost.reset` to clear entries for a specific spec.

## Development

```bash
# Install bats-core for running tests:
# macOS:  brew install bats-core
# Linux:  npm install -g bats  (or apt/dnf package)

# Run all tests:
bats tests/bats/

# Run a specific suite:
bats tests/bats/record.bats
```

## License

MIT — see [LICENSE](LICENSE).

## Community Catalog

To add this extension to your spec-kit catalog, submit an issue at
[spec-kit extension submission](https://github.com/github/spec-kit/issues/new?template=extension_submission.yml).
