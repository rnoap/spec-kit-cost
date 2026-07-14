<!--
SYNC IMPACT REPORT
==================
Version change:   1.0.0 → 1.1.0  (MINOR — new rule added to Development Workflow)
Bump rationale:   Rule 7 added to prevent AI agents from editing the spec-kit local
                  install directory (.specify/extensions/cost/) instead of repo root.

Modified principles:  none
Added sections:
  - Development Workflow: rule 7 (source-of-truth clarification)

Templates reviewed:
  ✅ .specify/templates/plan-template.md     — no changes required
  ✅ .specify/templates/spec-template.md     — no changes required
  ✅ .specify/templates/tasks-template.md    — no changes required

Deferred TODOs:    none
-->

# spec-kit-cost Constitution

## Core Principles

### I. Extension Contract First

The `extension.yml` manifest is the single source of truth for this extension's
public surface area. Every command, hook, config key, and version number MUST be
declared there before any implementation is written.

**Rules:**
- `extension.yml` MUST be updated in the same commit that adds or removes a command.
- Command names MUST follow the pattern `speckit.cost.<action>` (lowercase, hyphens only).
- The `schema_version` field MUST remain `"1.0"` until the upstream spec-kit schema
  increments.
- No behavior may be shipped that is not reflected in `extension.yml`; undocumented
  side-effects are a contract violation.

**Rationale:** Consumers (users, other extensions, CI) rely on the manifest to
understand what the extension provides. Drift between manifest and behavior creates
silent incompatibilities that are hard to debug and harder to review.

### II. Non-Destructive Tracking (NON-NEGOTIABLE)

The cost extension MUST NOT modify any file outside `.specify/extensions/cost/`.
It is a read-only observer with respect to `specs/`, `AGENTS.md`, `CLAUDE.md`,
and all project source files.

**Rules:**
- Writes are restricted to `.specify/extensions/cost/cost-ledger.jsonl` and
  `.specify/extensions/cost/cost-config.yml`.
- Commands MUST never call `git add`, `git commit`, `rm`, or destructive operations
  on spec or project files.
- Hook scripts MUST exit 0 even on failure (non-fatal) so they never block the
  primary workflow.

**Rationale:** An extension that silently corrupts spec files is worse than no
extension at all. Strict write isolation ensures the cost extension can be installed
and uninstalled without risk to existing project artifacts.

### III. Pluggable Data Source

Token count collection MUST be decoupled from persistence. The active provider is
configured in `cost-config.yml` and the implementation switches at runtime.

**Supported providers (v1.0.0):**
| Provider | Key | Description |
|---|---|---|
| Self-report | `self-report` | AI agent estimates tokens from content sizes (default) |
| Log file | `log-file` | Parse a provider-specific usage log file |
| Manual | `manual` | Developer supplies a count via `$ARGUMENTS` |

**Rules:**
- Default provider is `self-report`; the extension MUST work with zero configuration.
- New providers MAY be added in MINOR releases without breaking existing configs.
- Removing a provider requires a MAJOR version bump.
- Provider selection is read from `cost-config.yml`; environment variable
  `SPECKIT_COST_PROVIDER` overrides it at runtime.

**Rationale:** spec-kit runs on Claude, Copilot, Cursor, and other agents. Each has
a different mechanism for exposing token usage. A hardcoded provider would make the
extension useful only in one environment.

### IV. Append-Only Ledger

Cost entries are written to `.specify/extensions/cost/cost-ledger.jsonl` in
JSON Lines format, one record per workflow step, append-only.

**Record schema (v1):**
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
  "cost_usd": 0.0024,
  "note": ""
}
```

**Rules:**
- Records MUST be appended; existing lines MUST NOT be modified or deleted by hooks.
- `speckit.cost.reset` is the only command permitted to truncate the ledger, and it
  MUST prompt for confirmation before doing so.
- `speckit.cost.report` reads the ledger and outputs a human-readable summary;
  it never writes to the ledger.
- Schema version (`"v"`) MUST be incremented when field semantics change.

**Rationale:** Append-only ensures that partial or interrupted hook executions leave
a recoverable audit trail rather than corrupting the cost record.

### V. Shell-First, Zero Runtime Dependencies

All persistent operations (writing, reading, appending to the ledger) MUST be
implemented in POSIX-compatible Bash scripts. Markdown command files contain
AI-executed instructions only; they MUST NOT embed inline shell scripts.

**Rules:**
- Scripts MUST be placed in `scripts/bash/` and MUST be POSIX-compatible (no
  bash 5.x-only features without a feature guard).
- PowerShell variants MUST be provided in `scripts/powershell/` for Windows
  parity (can be added in a follow-up MINOR release).
- No external runtime dependencies (Python, Node.js, jq, etc.) are permitted in
  hook scripts. Pure `bash` + standard POSIX utilities only.
- AI command files (`.md`) MAY instruct the agent to call scripts via `bash
  .specify/extensions/cost/scripts/bash/<script>.sh`.

**Rationale:** spec-kit extensions run in diverse environments. Requiring a Node.js
or Python runtime would silently break the extension for developers who lack it.
Shell scripts with standard utilities (awk, grep, date, printf) work everywhere.

## Extension Compatibility Constraints

- **spec-kit version**: `>= 0.4.0` (hooks API stabilized in 0.4.0).
- **License**: MIT — all source files MUST include the MIT SPDX identifier.
- **Repository**: `https://github.com/rnoap/spec-kit-cost`
- **Community catalog**: Extension MUST be submitted to `catalog.community.json`
  via the official spec-kit issue template once v1.0.0 is released.
- **Semantic versioning**: MAJOR.MINOR.PATCH. No pre-release suffixes in catalog
  entries; use them only in development branches.
- **Language**: All code comments, documentation, README, and commit messages
  MUST be written in English.

## Development Workflow

This project follows spec-driven development (SDD) using spec-kit itself.

1. Every new feature or change begins with a spec in `specs/<NNN>-<name>/spec.md`.
2. Run `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, then `/speckit-implement`
   in order.
3. Feature branches follow `<NNN>-<kebab-name>` (managed by `speckit.git.feature`).
4. Commit after each spec-kit workflow step (managed by `speckit.git.commit` hooks).
5. PRs MUST reference the corresponding spec directory.
6. The extension MUST be self-hosting: development of spec-kit-cost SHOULD use
   spec-kit-cost's own hooks to track its build cost (dogfooding).
7. **This repository IS the extension source.** ALL implementation changes (scripts,
   commands, catalog, templates, manifests) MUST be made at the **repository root**.
   `.specify/extensions/cost/` is a spec-kit-managed local install regenerated by
   `specify extension add <path> --dev --force`; hand-editing it is prohibited because
   changes there are silently overwritten on reinstall. After any root change, reinstall
   the extension to keep the local copy in sync.

## Governance

- This constitution supersedes all other guidance documents in case of conflict.
- **Amendment procedure**: Open a PR that modifies this file, bumps the version
  line, and updates the Sync Impact Report comment at the top. At least one reviewer
  approval required before merging.
- **Versioning policy**: Follow semantic versioning rules defined in Principle I.
  Constitution version tracks document changes, not extension release versions.
- **Compliance review**: Every PR that adds or modifies a command, hook, or script
  MUST include a one-line statement confirming Principles I–V are satisfied.
- **Deviations**: Any deviation from a principle MUST be documented in a
  `specs/<NNN>-<name>/spec.md` with explicit justification before implementation.

**Version**: 1.1.0 | **Ratified**: 2026-07-13 | **Last Amended**: 2026-07-14
