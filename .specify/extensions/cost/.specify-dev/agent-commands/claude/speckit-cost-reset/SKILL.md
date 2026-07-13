---
name: speckit-cost-reset
description: Clear recorded cost entries for the current spec (requires confirmation).
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: cost:commands/speckit.cost.reset.md
---

# Reset Cost Entries

Clear all recorded cost entries for the current spec from the ledger.
This action is **irreversible** — cleared entries cannot be recovered.
Entries for other specs in the same ledger are not affected (CR-X2).

## Behavior

1. Displays a clear description of what will be deleted (spec name, scope).
2. Waits for **explicit human confirmation** before proceeding (FR-009, SC-006).
3. Only invokes the reset script if the developer explicitly confirms.
4. If the developer declines, reports that no data was changed.

## Execution

### Step 1 — Identify what will be cleared

Determine the current spec identifier from `.specify/feature.json`.
Present the following confirmation prompt to the developer:

---

> **Reset cost entries for `<spec-name>`?**
>
> This will permanently remove all recorded cost entries for this spec from the ledger.
> Entries for other specs are **not** affected.
> This action cannot be undone.
>
> Type `yes` to confirm, or anything else to cancel.

---

### Step 2 — Wait for explicit confirmation

Do **not** proceed automatically. The developer must type `yes` (case-insensitive)
to confirm. Any other response — including no response — is treated as a decline.

### Step 3a — If confirmed

Run:
```bash
bash .specify/extensions/cost/scripts/bash/reset-cost.sh --yes
```

Present the script's output to the developer. The script reports how many entries
were removed and how many entries for other specs were preserved.

### Step 3b — If declined

Report to the developer:
```
Reset cancelled. No cost data was changed.
```

Do not invoke the script.

## Graceful Degradation

- If the ledger does not exist, the script reports "nothing to reset" and exits 0.
- If the current spec has no entries, the script removes 0 entries and reports accordingly.