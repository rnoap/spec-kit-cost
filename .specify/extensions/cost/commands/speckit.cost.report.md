---
description: "Show the per-step cost breakdown and cumulative total for the current spec."
---

# Cost Report

Display a per-step cost breakdown table and cumulative USD total for the current spec.
This command is available at any time during or after the workflow (FR-006).
It is also wired to `after_implement` for automatic display after implementation completes (FR-007).

## Behavior

1. Reads the cost ledger at `.specify/extensions/cost/cost-ledger.jsonl`.
2. Filters entries to those belonging to the current spec only (FR-004, SC-004).
3. Renders a markdown table with one row per recorded step.
4. Prints the cumulative total in USD.
5. **Never writes to the ledger** (FR-010).

## Execution

Run the report script and present its complete output to the developer:

```bash
bash scripts/bash/report-cost.sh
```

Present the output as-is. The output format is:

```
## Cost Report: <spec-name>

| Step       | Input tokens | Output tokens | Cost (USD) |
|------------|-------------:|--------------:|-----------:|
| specify    |         1200 |           800 |    $0.0060 |
| clarify    |          800 |           400 |    $0.0036 |
...

**Total: $0.0240** (N step(s))
```

## Empty State

If no entries have been recorded for the current spec, the script prints:

```
No cost data recorded for this spec.
```

This is the expected output for a fresh install or after a reset (FR-017, SC-008).

## After Implement

When invoked by the `after_implement` hook, this command automatically shows the
full cumulative breakdown without any developer action required (FR-007, SC-005).

## On-Demand Usage

The developer may also invoke this command at any time (mid-workflow or after) using
the spec-kit command runner or by running the script directly.
