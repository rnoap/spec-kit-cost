# Feature Specification: Accurate Model-Aware Cost Calculation and Cumulative Report Table

**Feature Branch**: `002-improve-cost-accuracy`

**Created**: 2026-07-13

**Status**: Implemented (v1.2.0)

> **Amended by** [specs/003-tolerant-model-matching/spec.md](../003-tolerant-model-matching/spec.md)
> (v1.3.0, 2026-07-16): catalog lookup is now tolerant (not exact-match-only), and the
> final fallback rung is split $3/M input / $15/M output instead of a hardcoded blended
> rate — `price_per_1k` participates only when explicitly set. FR-004's ladder shape is
> unchanged; only the rung-3/4 semantics were refined.

**Input**: User description: "los costos que me arroja no son muy exactos y por ejemplo si ocupo un modelo pesado como opus 4.8 los valores que me arroja se que son incorrectos ya que cuesta mucho más y los tokens que me dice que gasto se que valen mucho más. como podemos mejorar el calculo que hace nuextra extension?? también mejoremos para que la tabla de cost report muestre el total hasta el momento además del total por step"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero-Config Accurate Cost via Model Catalog (Priority: P1)

A developer using Claude Opus 4.8 finishes a spec-kit workflow step. The extension reports a cost of $0.135, but their actual billing shows the step cost several times more. The root cause: the extension uses a single blended rate of $0.003 per 1,000 tokens regardless of which model is active. Output tokens are significantly more expensive than input tokens for premium models, and different models have very different price points.

The developer should not have to open `cost-config.yml` and look up pricing tables to get an accurate reading. The extension ships with a catalog of known model prices. The model active during the workflow step is detected automatically from the harness-injected context before the hook fires. The catalog prices are applied — no configuration required.

**Why this priority**: Cost data that is materially wrong erodes trust in the tool and makes it useless for budget tracking. For a developer using a premium model, the current estimate can be less than 30% of the real cost. This is the minimum bar for the extension to deliver any value.

**Independent Test**: With no changes to `cost-config.yml`, run a workflow step with a known model (e.g., Claude Sonnet 4.6 or GPT-4o). Verify that the reported cost matches the independently computed value using the known model's separate input and output rates to four decimal places — without any manual configuration.

**Acceptance Scenarios**:

1. **Given** the extension is installed with no `cost-config.yml` changes, **When** a workflow step completes with a model present in the catalog, **Then** the cost is computed as `(input_tokens × catalog_input_rate) + (output_tokens × catalog_output_rate)` using the catalog prices for that model, with no manual setup required.
2. **Given** the active model is a known Wibey-supported model (e.g., claude-opus-4-8, claude-sonnet-4-6, claude-haiku-4-5), **When** the cost record hook fires, **Then** the model is correctly identified and its catalog prices are applied before the cost is written to the ledger.
3. **Given** the active model is not found in the catalog, **When** the hook fires, **Then** a non-fatal warning is emitted naming the unrecognized model, and the system falls back to the configured `price_per_1k` (or the hardcoded default) so the workflow is never blocked.

---

### User Story 2 - Manual Rate Override for Custom or Unknown Models (Priority: P2)

A developer uses a model not yet in the catalog, or wants to track cost using their actual negotiated enterprise rate rather than the published list price. They configure `input_rate_per_1k` and `output_rate_per_1k` (or the legacy `price_per_1k`) in `cost-config.yml` to override catalog prices for their setup.

**Why this priority**: The catalog covers all Wibey-supported models at release, but new models and enterprise pricing arrangements require a manual escape hatch. This is lower priority than the catalog because it requires developer action and the catalog handles the common case automatically.

**Independent Test**: Configure `input_rate_per_1k: 0.010` and `output_rate_per_1k: 0.030` in `cost-config.yml`. Run a workflow step. Verify the reported cost uses those exact rates regardless of which model is detected.

**Acceptance Scenarios**:

1. **Given** `input_rate_per_1k` and `output_rate_per_1k` are both set in `cost-config.yml`, **When** a step is recorded, **Then** those values override any catalog price for the detected model and cost is computed as `(input_tokens × input_rate_per_1k / 1000) + (output_tokens × output_rate_per_1k / 1000)`.
2. **Given** only `price_per_1k` is set in `cost-config.yml` (no separate rates), **When** a step is recorded, **Then** the blended formula `(input_tokens + output_tokens) × price_per_1k / 1000` is used — backward compatibility is preserved.
3. **Given** an existing project that has never modified `cost-config.yml`, **When** the extension upgrade is applied, **Then** behavior is unchanged (catalog now applies instead of the old blended default, which is a net improvement, but no config file changes are required).

---

### User Story 3 - Cumulative Running Total in Report Table (Priority: P3)

A developer reviews the cost breakdown table at the end of a multi-step workflow. They can see the cost per step and the grand total at the bottom, but identifying when cost started accumulating rapidly requires mentally summing rows. A cumulative column showing the running total through each row removes that mental arithmetic.

**Why this priority**: Per-step costs and the grand total already exist. This is a readability improvement that directly addresses the second part of the user's request and requires no configuration change.

**Independent Test**: Run the cost report with three or more recorded steps. Verify that the cumulative column value for each row equals the sum of the Cost (USD) column for that row and all rows above it, and that the final row's cumulative value equals the grand total printed below the table.

**Acceptance Scenarios**:

1. **Given** the cost report is generated for a spec with N recorded steps, **When** the report table renders, **Then** a "Cumulative" column appears showing the running total through each row, and the value in the last row equals the grand total printed below the table.
2. **Given** a spec with a single recorded step, **When** the report renders, **Then** the cumulative column value equals the per-step cost, and the grand total matches.
3. **Given** any rendered report, **When** a developer reads the table, **Then** the grand total line below the table continues to appear and matches the cumulative value in the last row.

---

### Edge Cases

- What happens when the model catalog is absent or corrupted? The extension emits a non-fatal warning and falls back to the configured rates (or hardcoded defaults), never blocking the workflow.
- What happens when the model cannot be detected from the harness context? The extension records `model: unknown`, emits a non-fatal warning, and applies the configured or default rate fallback.
- What happens when `input_rate_per_1k` and `output_rate_per_1k` are both absent but `price_per_1k` is also absent, and no catalog match exists? The extension must fall back to the hardcoded default blended rate.
- What happens when only one of `input_rate_per_1k` / `output_rate_per_1k` is configured manually? The configured key applies to its token type; the absent key falls back to the catalog rate (if available) or `price_per_1k` (or the hardcoded default if that is also absent). No warning is emitted for partial manual config — it is valid and intentional.
- What happens when stored token counts are zero for a step? The cumulative column must show $0.0000 for that row without errors.
- What happens if the ledger contains entries recorded under the old blended-rate scheme? The report recomputes all entries from stored token counts using current rates, so the display is consistent across all rows regardless of when they were written.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The extension MUST ship with a pre-populated model price catalog covering all Wibey-supported Claude models AND widely-used OpenAI models available on OpenAI's API pricing page at the time of implementation, each with their separate input and output token rates.
- **FR-002**: Before recording cost for any step, the extension MUST detect the active model from the harness-injected context available to the AI agent executing the hook. This is the authoritative signal; the AI does not guess or self-identify — it reads the value injected by the Wibey harness.
- **FR-003**: When a detected model is found in the catalog, cost MUST be computed as `(input_tokens × catalog_input_rate) + (output_tokens × catalog_output_rate)`. No manual configuration is required.
- **FR-004**: Rate resolution for a given token type MUST follow this priority order (highest to lowest): (1) matching manual config key (`input_rate_per_1k` for input, `output_rate_per_1k` for output); (2) catalog rate for the detected model; (3) legacy blended `price_per_1k`; (4) hardcoded default rate. Each token type resolves independently, enabling partial overrides.
- **FR-005**: When a detected model is NOT found in the catalog, the extension MUST emit a non-fatal warning to stderr naming the unrecognized model, then apply FR-004 fallback logic. The workflow MUST NOT be blocked.
- **FR-006**: The model catalog MUST be a plain-text file parseable using only POSIX shell utilities (grep, cut, awk, sed) — no external parsers. Each entry contains the model ID, input rate, and output rate in a fixed, documented format.
- **FR-007**: The catalog MUST be updatable by modifying a single file distributed with the extension, without changing any shell scripts or command files.
- **FR-008**: The cost report MUST recompute per-step cost from stored `input_tokens`, `output_tokens`, and the stored `model` field using the current active rates at report time, rather than using the stored `cost_usd` value. This allows rate corrections (catalog update or config change) to be reflected immediately on rerun.
- **FR-009**: The cost report table MUST include a "Cumulative" column containing the running total cost through each row, formatted to four decimal places in USD.
- **FR-010**: The grand total line below the report table MUST continue to appear and MUST equal the cumulative value in the final row.
- **FR-011**: All detection, lookup, and validation failures MUST be non-blocking: the extension prints a warning to stderr and falls back gracefully. Hook exit code is always 0.

### Key Entities

- **Model Catalog**: A plain-text file shipped with the extension. Contains one entry per known model with its model ID, input token rate, and output token rate. Two authoritative pricing sources are used: the Wibey CLI's model pricing constants (`src/constants/models.ts` in the wibey-cli repository) for Claude models, and OpenAI's published API pricing page for OpenAI models. The catalog is provider-agnostic — any model ID string is a valid key.
- **Detected Model**: The model ID extracted from the Wibey harness-injected context by the AI agent executing the cost record hook. Stored in each ledger entry as the `model` field.
- **Cost Configuration**: The optional `cost-config.yml` file. Contains `input_rate_per_1k`, `output_rate_per_1k`, and/or the legacy `price_per_1k` as manual overrides. All keys are optional — the catalog handles the common case.
- **Ledger Entry**: A single append-only record for one workflow step. Contains `input_tokens`, `output_tokens`, `model` (detected at record time), and `cost_usd` (informational — the report recomputes from token counts + stored model + current rates).
- **Report Row**: One line in the rendered cost table. Includes Step, Input Tokens, Output Tokens, Cost (USD) recomputed at current rates, and Cumulative Total.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With no changes to `cost-config.yml`, a developer using any Wibey-supported model sees a reported cost that matches the expected value computed from the model's known input and output rates to four decimal places.
- **SC-002**: The cost reported for a premium model (e.g., Opus 4.8) is visibly and materially different from the cost reported for an economy model (e.g., Haiku 4.5) given the same token counts, reflecting the true price difference between models.
- **SC-003**: Correcting the catalog or config and rerunning the report immediately reflects the corrected cost for all previously recorded steps of the current spec, without re-running any workflow steps.
- **SC-004**: The cumulative column value in the last row of the report table always equals the grand total printed below the table, verifiable by inspection.
- **SC-005**: An existing project that upgrades to this version with no config changes continues to produce reports without errors. Cost figures improve (become more accurate) because the catalog now applies, but no setup is required.
- **SC-006**: The extension never blocks a workflow step due to a model detection failure, catalog miss, or rate configuration error — all failures produce a warning on stderr and the workflow proceeds.

## Clarifications

### Session 2026-07-13

- Q: When `price_per_1k`, `input_rate_per_1k`, and `output_rate_per_1k` are all present in the config, which rate formula should be used? → A: Separate rates always win — `input_rate_per_1k` + `output_rate_per_1k` take priority over `price_per_1k` when both are present. (Superseded by FR-004 priority order which adds catalog as an intermediate layer.)
- Q: When exactly one of `input_rate_per_1k` / `output_rate_per_1k` is present, what should happen? → A: Use the configured rate for the present key; fall back to the catalog rate (or `price_per_1k`, or the hardcoded default) for the absent key — partial improvement applies immediately.
- Q: When the report recomputes costs at runtime, which ledger entries does it recompute — current spec only, or all specs? → A: Current spec only — same filter as today; recomputation applies to that subset.
- Q: Should `input_rate_per_1k` and `output_rate_per_1k` be overridable via environment variables (like `SPECKIT_COST_PROVIDER`)? → A: No — config file only for this feature; env var override support is deferred to a future spec.

## Assumptions

- Authoritative pricing sources for the initial catalog: (1) Claude models → Wibey CLI `src/constants/models.ts` (USD per million tokens — Opus 4.8/4.6: $5 input / $25 output, Sonnet family: $3 input / $15 output, Haiku 4.5: $1 input / $5 output); (2) OpenAI models → OpenAI's published API pricing page, verified at implementation time (not from training-data recall). The catalog must be checked against these sources at implementation and on each catalog update, not assumed from memory.
- The OpenAI models included in the initial catalog are the widely-used models available on OpenAI's API pricing page as of the implementation date. As of 2026-07-13, the live page lists the `gpt-5.6-*`, `gpt-5.5`, `gpt-5.4-*`, and `o4-mini` families (classic `gpt-4o`/`o1`/`o3` are no longer listed). Exact model IDs and prices are confirmed from `research.md` § Catalog Data Sources; the spec does not hardcode them to avoid stale names.
- Model identity is detected by the AI agent from the Wibey harness-injected system context (the "Current model: <model-id>" value present in the agent's session). This is an authoritative harness signal, not the model's own self-belief.
- The auto-elite and auto-economy virtual model IDs (which route to a dual executor+advisor pair) are NOT in the catalog as primary entries. If detected, the extension falls back to the executor model's price or the default rate. This avoids double-counting cost for the advisor model, which the harness accounts for separately.
- The `self-report` provider's chars ÷ 4 token estimation remains as-is. Improving token count accuracy (e.g., reading actual counts from provider logs) is out of scope for this feature.
- The ledger schema (`"v": 1`) does not change. No migration of existing ledger files is required because the report recomputes costs from stored token counts and model IDs at read time.
- The report displays entries for the current spec only (identified by `.specify/feature.json`), consistent with existing behavior.
- Configuration parsing remains pure Bash + standard POSIX utilities (no external parsers), consistent with Constitution §V. The catalog format must be parseable with these tools.
- Environment variable overrides for rate keys (`input_rate_per_1k`, `output_rate_per_1k`) are out of scope for this feature. Only the config file and the catalog control rate values.
- The `cost_usd` field continues to be written to the ledger at record time using the best available rate at that moment, for audit trail purposes. The report recomputes from token counts regardless.
