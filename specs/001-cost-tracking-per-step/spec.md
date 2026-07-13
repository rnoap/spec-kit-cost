# Feature Specification: Cost Tracking Per Workflow Step with Cumulative Total

**Feature Branch**: `001-cost-tracking-per-step`

**Created**: 2026-07-13

**Status**: Draft

**Input**: User description: "Cost tracking per workflow step with cumulative total — the extension hooks into all spec-kit lifecycle events, records token cost to an append-only ledger, shows a brief inline cost summary after each step, and displays a full cost breakdown table plus cumulative total in USD after implement (or on-demand via a report command). Provides reset and report commands. Primary data source is self-report (the AI agent estimates tokens from visible content) with a configurable price-per-1k-tokens."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See running cost after each workflow step (Priority: P1)

A developer running the spec-kit SDD workflow (specify → clarify → plan → tasks → analyze → checklist → implement) wants immediate visibility into how many LLM tokens each step consumed and what that cost, so they can notice expensive steps as they happen rather than discovering the total at the end.

**Why this priority**: This is the core value of the extension — per-step cost visibility. Without it, the extension provides nothing. It is the minimum viable slice: a developer who only ever sees inline per-step summaries already gets the primary benefit (real-time cost awareness) even if no other feature exists.

**Independent Test**: Run any single spec-kit workflow step (e.g., `specify`) in a project where the cost extension is installed with zero configuration. Confirm that after the step completes, a brief inline cost summary appears showing the step name, estimated token counts, and estimated cost in USD, and that a corresponding entry is appended to the cost ledger.

**Acceptance Scenarios**:

1. **Given** the cost extension is installed with no `cost-config.yml` present, **When** the developer completes the `specify` step for a spec, **Then** a brief inline summary shows the step name, estimated input/output token counts, and the estimated cost in USD for that step, using default configuration.
2. **Given** a spec workflow already has prior recorded steps, **When** the developer completes a later step (e.g., `plan`), **Then** a new entry is appended to the ledger without altering any existing entry, and the inline summary reflects only the just-completed step.
3. **Given** the token estimation for a step cannot be produced for any reason, **When** the step completes, **Then** the workflow continues uninterrupted and the failure does not block or fail the primary spec-kit step.
4. **Given** each of the seven supported lifecycle events (`after_specify`, `after_clarify`, `after_plan`, `after_tasks`, `after_analyze`, `after_checklist`, `after_implement`), **When** that event fires, **Then** a cost entry tagged with the corresponding step name is recorded and an inline summary is displayed.

---

### User Story 2 - View a cumulative cost breakdown for the whole spec (Priority: P2)

A developer who has completed (or partially completed) a spec's workflow wants a consolidated view of every step's cost and a cumulative total in USD, so they can report or reason about the total cost of producing that spec.

**Why this priority**: The cumulative total is the second-most valuable outcome, but it depends on per-step entries existing first (User Story 1). It delivers standalone value: even mid-workflow, a developer can ask for the current running total.

**Independent Test**: With at least two recorded steps for a spec in the ledger, invoke the on-demand report command and confirm it prints a per-step breakdown table plus a cumulative total in USD covering all entries for the current spec — without requiring any workflow step to run.

**Acceptance Scenarios**:

1. **Given** the ledger contains multiple recorded steps for the current spec, **When** the developer invokes `speckit.cost.report`, **Then** a breakdown table lists each step with its token counts and per-step cost, followed by a cumulative total in USD for the current spec.
2. **Given** the `implement` step has just completed, **When** the `after_implement` event fires, **Then** the full cumulative cost breakdown for the current spec is displayed automatically (in addition to the inline per-step summary), without the developer needing to run the report command manually.
3. **Given** the ledger contains entries for more than one spec, **When** the developer runs `speckit.cost.report` for the current spec, **Then** only entries belonging to the current spec are consolidated into the breakdown and total.
4. **Given** the ledger has no entries for the current spec, **When** the developer runs `speckit.cost.report`, **Then** a clear "no cost data recorded for this spec" message is shown instead of an empty or misleading table.

---

### User Story 3 - Reset the cost ledger for a spec session (Priority: P3)

A developer who wants to restart cost tracking for a spec (e.g., after re-running the workflow, or to clear estimates from a discarded attempt) wants to clear the recorded cost entries deliberately and safely.

**Why this priority**: Reset is a housekeeping convenience, valuable but not required for the core measure-and-report loop. It is lowest priority because the append-only ledger remains usable and reportable without it.

**Independent Test**: With existing ledger entries for a spec, invoke `speckit.cost.reset`, confirm the command requires explicit confirmation before clearing, and confirm that after confirmation a subsequent report shows no recorded data for that spec.

**Acceptance Scenarios**:

1. **Given** the ledger contains entries for the current spec, **When** the developer invokes `speckit.cost.reset`, **Then** the command prompts for explicit confirmation before clearing any data.
2. **Given** the reset confirmation prompt is shown, **When** the developer declines, **Then** no entries are removed and the ledger is unchanged.
3. **Given** the reset confirmation prompt is shown, **When** the developer confirms, **Then** the ledger entries for the spec session are cleared and a subsequent `speckit.cost.report` reports no recorded data for that spec.

---

### Edge Cases

- **No prior configuration**: When `cost-config.yml` does not exist, the extension MUST operate using documented default values (default provider `self-report`, default price-per-1k-tokens, default model label) so it works with zero configuration.
- **Estimation failure**: When the AI agent cannot produce a token estimate for a step, the step still records nothing harmful and the primary workflow is never blocked.
- **Empty ledger on report**: Reporting when no entries exist for the current spec yields an explicit empty-state message, not an error or blank output.
- **Report before any step**: Running `speckit.cost.report` before any workflow step has run for the spec behaves the same as the empty-ledger case.
- **Multiple specs in one ledger**: Entries from different specs coexist in the single ledger file; per-spec reporting isolates the current spec's entries.
- **Interrupted step**: If a workflow step is interrupted after the primary work but before a cost entry is written, the append-only ledger remains valid and the next step records normally.
- **Manual and log-file providers**: When a non-default provider is configured but its required input (a supplied count for `manual`, or a readable usage log for `log-file`) is unavailable, the extension records what it can without blocking the workflow.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The extension MUST record a cost entry for each of the seven supported spec-kit lifecycle events: `after_specify`, `after_clarify`, `after_plan`, `after_tasks`, `after_analyze`, `after_checklist`, and `after_implement`.
- **FR-002**: After each supported lifecycle event, the extension MUST display a brief inline cost summary for that step, including the step name, estimated input and output token counts, and the estimated cost in USD.
- **FR-003**: Each recorded cost entry MUST be appended to the cost ledger without modifying or deleting any existing entry (append-only).
- **FR-004**: Each cost entry MUST be associated with the spec it belongs to, so that entries for different specs can be distinguished during reporting.
- **FR-005**: The extension MUST provide an on-demand `speckit.cost.report` command that consolidates all recorded entries for the current spec and displays a per-step breakdown table plus a cumulative total in USD.
- **FR-006**: The `speckit.cost.report` command MUST NOT depend on any lifecycle hook and MUST be runnable at any time (including mid-workflow).
- **FR-007**: After the `implement` step completes, the extension MUST automatically display the full cumulative cost breakdown and total for the current spec, in addition to the inline per-step summary.
- **FR-008**: The extension MUST provide a `speckit.cost.reset` command that clears the recorded cost entries for a spec session.
- **FR-009**: The `speckit.cost.reset` command MUST require explicit confirmation from the developer before clearing any data, and MUST leave the ledger unchanged if confirmation is declined.
- **FR-010**: The `speckit.cost.report` command MUST only read cost data and MUST NOT write to the ledger.
- **FR-011**: The extension MUST support a configurable price-per-1k-tokens value read from the extension configuration, and MUST use a documented default value when no configuration is present.
- **FR-012**: The extension MUST support selecting a token-count data source (provider), defaulting to `self-report`, and MUST also support `log-file` and `manual` providers. The configured provider selection MAY be overridden at runtime for a single invocation.
- **FR-013**: With the default `self-report` provider, the extension MUST estimate token counts based on the visible content of the step (approximate prompt size and response size) without requiring any external usage data.
- **FR-014**: The extension MUST function with zero configuration — installing it and running the workflow MUST produce per-step summaries and reports using default settings alone.
- **FR-015**: A failure in cost tracking (estimation, recording, or display) MUST NOT block, fail, or interrupt the primary spec-kit workflow step.
- **FR-016**: The extension MUST NOT modify any file outside its own extension data directory; it MUST be a read-only observer of specs, agent guidance files, and project source files.
- **FR-017**: When reporting for a spec that has no recorded entries, the extension MUST display an explicit empty-state message rather than an empty or misleading table.
- **FR-018**: Each cost entry MUST capture, at minimum, a timestamp, the step name, the spec identifier, the provider used, the input and output token counts, the model label, and the computed cost in USD.

### Key Entities *(include if feature involves data)*

- **Cost Entry**: A single record of one workflow step's estimated cost. Attributes: timestamp, step name (one of the seven lifecycle events), spec identifier, provider, input token count, output token count, model label, cost in USD, and an optional note. One entry is produced per lifecycle event occurrence.
- **Cost Ledger**: The append-only collection of Cost Entries for the project, stored as one record per line. It is the durable source of truth from which reports are consolidated. It may contain entries from multiple specs.
- **Cost Configuration**: The developer-adjustable settings that govern cost computation and collection. Attributes: active provider (`self-report`, `log-file`, or `manual`), price-per-1k-tokens, and default model label. Absent configuration falls back to documented defaults.
- **Cost Report**: A consolidated, human-readable view derived from the ledger for a single spec — a per-step breakdown table plus a cumulative total in USD. It is a read-only projection and is never persisted back to the ledger.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After each of the seven supported workflow steps completes, a per-step cost summary is displayed exactly once, showing step name, token counts, and USD cost.
- **SC-002**: A developer can install the extension and see a correct per-step cost summary on the very first workflow step with no configuration file present (zero-config success).
- **SC-003**: Running the report command produces a breakdown that lists every recorded step for the current spec, and its cumulative total equals the sum of the per-step USD costs for that spec.
- **SC-004**: When entries exist for more than one spec, the report for the current spec includes only that spec's entries (0 entries from other specs appear in the total).
- **SC-005**: Completing the `implement` step results in the full cumulative breakdown being shown automatically, with no separate manual command required.
- **SC-006**: The reset command never removes data without explicit confirmation — declining the prompt leaves 100% of existing entries intact.
- **SC-007**: A forced failure in cost tracking during any step does not change the outcome of the primary spec-kit step (the workflow step still succeeds).
- **SC-008**: Requesting a report for a spec with no recorded entries yields a clear empty-state message and never an error.

## Assumptions

- **Constitution-derived constraints (fixed, not open decisions)**: The following are already ratified in the project constitution (v1.0.0) and are treated as fixed inputs to this spec, not as implementation choices:
  - Command names are `speckit.cost.report` and `speckit.cost.reset` (pattern `speckit.cost.<action>`).
  - The ledger is stored append-only as JSON Lines at `.specify/extensions/cost/cost-ledger.jsonl`.
  - Configuration is read from `.specify/extensions/cost/cost-config.yml`.
  - The extension writes only within `.specify/extensions/cost/`.
  - Supported providers are `self-report` (default), `log-file`, and `manual`.
  - Cost is expressed in USD, computed from a price-per-1k-tokens value.
  - The cost-entry record schema includes the fields listed in FR-018 (per the constitution's record schema v1).
- **Self-report estimation approach**: With the default `self-report` provider, token counts are approximations derived from the visible content sizes the AI agent has access to (prompt and response). These are estimates, not exact provider-billed counts; the spec treats them as "best-effort estimates" and does not require billing-grade accuracy.
- **Default configuration values**: When `cost-config.yml` is absent, the extension uses a documented default provider (`self-report`), a documented default price-per-1k-tokens, and a documented default model label. The exact default numeric price and model label are configuration details to be finalized in planning; the requirement is only that documented defaults exist and the extension works without configuration.
- **Spec identity**: The "current spec" is determined from the active spec-kit feature context (the same context spec-kit itself uses to locate the feature directory). Cost entries are tagged with that identifier.
- **Single project scope**: Cost tracking operates per project (per repository). Aggregating costs across multiple repositories is out of scope for this feature.
- **spec-kit version**: The host environment provides spec-kit `>= 0.4.0` with a stable hooks API, and fires the seven lifecycle events this feature relies on.
- **Provider inputs for non-default providers**: `manual` expects a developer-supplied count; `log-file` expects a readable provider usage log. Sourcing or formatting those inputs beyond what the constitution defines is deferred to planning.
- **Out of scope for v1**: Multi-currency support, cost budgets/alerts/thresholds, historical trend charts, and cross-spec aggregate dashboards are not part of this feature.
