# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial spec-kit project setup with `specify init` (integration: claude)
- Project constitution v1.0.0 — five core principles ratified:
  - I. Extension Contract First
  - II. Non-Destructive Tracking (non-negotiable)
  - III. Pluggable Data Source (self-report / log-file / manual)
  - IV. Append-Only Ledger (JSON Lines in `cost-ledger.jsonl`)
  - V. Shell-First, Zero Runtime Dependencies
- `.wibey/skills/` — 19 spec-kit project skills synced and committed
- `specs/` directory scaffolded for spec-driven development
- `AGENTS.md` — Wibey/AI context file with graph-priority section
- `.gitignore` — excludes `.claude/` (machine-local skill copies)
- `git` extension installed (`speckit.git.*` commands)
- `brownfield` extension installed (`speckit.brownfield.*` commands)
- Code knowledge graph built (`.code-review-graph/`)

---

<!-- CHANGELOG GUIDE
===================
Sections (use only what applies to each release):
  ### Added       — new features
  ### Changed     — changes to existing functionality
  ### Deprecated  — features to be removed in a future release
  ### Removed     — features removed in this release
  ### Fixed       — bug fixes
  ### Security    — security-related fixes

Versioning rules (from constitution Principle I):
  MAJOR — backward-incompatible manifest/hook/command changes
  MINOR — new commands, hooks, or config keys added
  PATCH — bug fixes, doc clarifications, script corrections

Release entry template:
  ## [X.Y.Z] - YYYY-MM-DD
  ### Added
  - ...
  ### Changed
  - ...

Link definitions (update on each release):
  [Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/vX.Y.Z...HEAD
  [X.Y.Z]: https://github.com/rnoap/spec-kit-cost/compare/vA.B.C...vX.Y.Z
-->

[Unreleased]: https://github.com/rnoap/spec-kit-cost/compare/HEAD...HEAD
