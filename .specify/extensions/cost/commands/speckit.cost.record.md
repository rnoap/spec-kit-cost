---
description: "Compute and record the cost of the just-completed workflow step."
---

# Record Step Cost

Estimate the token cost of the workflow step that just completed and append one entry
to the cost ledger. Prints a single-line inline summary to the developer.

## Behavior

This command is invoked as an `after_*` hook by spec-kit. It:

1. Determines the step name from the hook event that triggered it
   (e.g., if called as `after_specify`, the step is `after_specify`).
2. Resolves the active provider: `SPECKIT_COST_PROVIDER` env → `cost-config.yml` → `self-report`.
3. Gathers token count inputs based on the active provider (see Provider Branches below).
4. Invokes `bash scripts/bash/record-cost.sh` with the gathered inputs.
5. Presents the script's stdout output — one `💰` summary line — to the developer.
6. Does **not** suppress stderr (warnings about skipped entries appear as-is).

## Execution

### Step 1 — Determine the lifecycle event name

Identify which `after_*` hook fired this command. The step name is one of:
`after_specify`, `after_clarify`, `after_plan`, `after_tasks`,
`after_analyze`, `after_checklist`, `after_implement`.

### Step 2 — Resolve provider

Check `SPECKIT_COST_PROVIDER` environment variable first.
If unset, read `provider` from `.specify/extensions/cost/cost-config.yml`.
If absent, use `self-report` (default).

### Step 3a — Detect active model (FR-002)

This extension runs on any AI coding assistant (Wibey, GitHub Copilot, Cursor, etc.).
Identify the canonical API model ID using whichever signal is available, in this order:

**1. Harness injection (Wibey / Claude Code)**
Look for a line matching `Current model: <Display Name> (<model-id>)` in your session
context. Extract the model ID from the parenthetical:
`Current model: Claude Sonnet 4 (claude-sonnet-4-6)` → `claude-sonnet-4-6`

**2. Host agent context (GitHub Copilot, Cursor, others)**
Look for any explicit model identifier in your system prompt or context provided by
the host agent. Common formats: `Model: gpt-5.4`, `Using model: gemini-2.5-pro`,
or a model field in the agent's instructions.

**3. Self-identification**
You know what model you are. Use the canonical API model ID — not the display name.
Examples:
- Claude Sonnet 4.6 → `claude-sonnet-4-6`
- GPT-5.4 → `gpt-5.4`
- Gemini 2.5 Pro → `gemini-2.5-pro`

Cross-reference with `.specify/extensions/cost/model-catalog.txt` to confirm the
exact ID string that will match a catalog entry.

**4. Fallback**
Read `model` from `.specify/extensions/cost/cost-config.yml`. If absent or `unknown`,
use `unknown` (triggers a warning and applies the blended fallback rate).

Store the result as `<MODEL_ID>` and include `--model <MODEL_ID>` in every script
invocation below.

### Step 3 — Provider branch: gather inputs

**`self-report` (default)**

Estimate the character count of:
- **Input content**: the spec file(s), user prompt, and any context visible at the
  start of this step (approximate total characters passed into the AI for this step).
- **Output content**: the AI's response generated during this step (approximate total
  characters in the output produced).

Use the number of characters as `<IN_CHARS>` and `<OUT_CHARS>` respectively.

Run:
```bash
bash scripts/bash/record-cost.sh \
  --step <STEP_NAME> \
  --model <MODEL_ID> \
  --in-chars <IN_CHARS> \
  --out-chars <OUT_CHARS>
```

**`manual`**

Ask the developer:
> "How many tokens did this step use? Please provide input and output token counts."

Wait for the developer's response. Use the supplied values as `<IN_TOKENS>` and `<OUT_TOKENS>`.

Run:
```bash
bash scripts/bash/record-cost.sh \
  --step <STEP_NAME> \
  --model <MODEL_ID> \
  --provider manual \
  --in-tokens <IN_TOKENS> \
  --out-tokens <OUT_TOKENS>
```

**`log-file`**

Run (the script emits a non-blocking warning; the entry is skipped in v1.0.0):
```bash
bash scripts/bash/record-cost.sh \
  --step <STEP_NAME> \
  --model <MODEL_ID> \
  --provider log-file
```

### Step 4 — Present output

Display the script's stdout to the developer. The inline summary format is:
```
💰 <step>: ~N in / ~N out tokens ≈ $N.NNNN
```

## Graceful Degradation

If the script exits with any error (it will not — it always exits 0) or if the
estimation cannot be performed, the workflow continues uninterrupted. The script
handles all failures internally and prints a `⚠️  speckit-cost:` warning to stderr.
