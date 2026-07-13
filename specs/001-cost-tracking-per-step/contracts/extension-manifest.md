# Contract: Extension Manifest (`extension.yml`)

**Feature**: `001-cost-tracking-per-step`

The manifest is the single source of truth for the extension's public surface
(Constitution §I). This contract fixes its shape. The manifest below is authored in the
**source repository root**; on install it provisions the runtime layout under
`.specify/extensions/cost/`.

## Required manifest shape

```yaml
schema_version: "1.0"          # fixed until upstream spec-kit schema increments (§I)
id: cost
name: spec-kit-cost
version: "1.0.0"
description: >
  Tracks estimated LLM token cost per spec-kit workflow step, appends an
  append-only USD ledger, and reports a cumulative per-spec breakdown.
author: rnoap
repository: https://github.com/rnoap/spec-kit-cost
license: MIT

requires:
  speckit_version: ">=0.4.0"   # Constitution: hooks API stabilized in 0.4.0

provides:
  commands:
    - id: speckit.cost.record
      description: Compute and record the cost of the just-completed workflow step.
    - id: speckit.cost.report
      description: Show the per-step cost breakdown and cumulative total for the current spec.
    - id: speckit.cost.reset
      description: Clear recorded cost entries for the current spec (requires confirmation).
  config:
    template: config-template.yml           # source filename
    install_path: cost-config.yml           # installed as .specify/extensions/cost/cost-config.yml
    keys:
      - name: provider
        default: self-report
        enum: [self-report, log-file, manual]
      - name: price_per_1k
        default: 0.003
      - name: model
        default: unknown

hooks:
  after_specify:    [speckit.cost.record]
  after_clarify:    [speckit.cost.record]
  after_plan:       [speckit.cost.record]
  after_tasks:      [speckit.cost.record]
  after_analyze:    [speckit.cost.record]
  after_checklist:  [speckit.cost.record]
  after_implement:  [speckit.cost.record, speckit.cost.report]   # FR-007: auto full breakdown

tags: [cost, tokens, budget, observability, ledger]
```

## Contract rules

- **CR-M1**: Command IDs MUST follow `speckit.cost.<action>` (Constitution §I).
- **CR-M2**: All three commands and all seven `after_*` hooks MUST be declared here; no
  behavior may ship that is not reflected in the manifest (Constitution §I, FR-001).
- **CR-M3**: `after_implement` MUST wire **both** `speckit.cost.record` and
  `speckit.cost.report`, in that order (FR-007, SC-005).
- **CR-M4**: The config block MUST declare the three keys with the defaults from
  data-model.md, enabling zero-config operation (FR-014).
- **CR-M5**: `schema_version` MUST remain `"1.0"`; `requires.speckit_version` MUST be
  `>=0.4.0`.

## Relationship to the repo's own `.specify/extensions.yml`

This `extension.yml` is the **product** of this repository. It is distinct from
`/.specify/extensions.yml`, which wires the `git` and `brownfield` extensions used to
*build* this repo. The two files MUST NOT be conflated.
