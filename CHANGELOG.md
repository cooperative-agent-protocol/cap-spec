<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Changelog — `cap-spec`

All notable changes to the CAP (Cooperative Agent Protocol) specification will
be documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
per [ADR-008](docs/adr/008-versioning.md).

## [Unreleased]

### Added
- ADR-012: Rationale for keeping `mean_field.proto` in CAP-Core rather than
  the Construction Domain Pack.
- ADR-011: Domain Pack Architecture — formal Core / Domain Pack boundary.
- ADR-010: Observability — OpenTelemetry semantic conventions for CAP.
- ADR-009: Relationship to OPC UA and OPC UA Companion Specification for
  Construction.
- ADR-008: Versioning and deprecation policy.
- `rfcs/` directory with RFC-0000 template and Domain Pack proposal
  template.
- `SECURITY.md` with vulnerability disclosure process + CNA registration
  roadmap.
- `proto/cap/v0/domains/construction/{skills,zones,equipment}.proto` —
  Construction Domain Pack v0 schemas.
- SPDX-License-Identifier headers across all source files (Apache-2.0).
- buf.yaml `name: buf.build/cap-protocol/cap-core` for BSR module
  reservation.

### Changed
- **Rebrand**: "Construction Agent Protocol" → "Cooperative Agent Protocol"
  across all docs, READMEs, and package descriptions. CAP is now positioned
  as domain-agnostic with Construction as the v0 reference Domain Pack.
- **Proto namespace reorganization**: `cap.v0.*` → `cap.v0.core.*`. All 16
  proto files relocated from `proto/cap/v0/` to `proto/cap/v0/core/`.
  Python imports `from cap.v0 import ...` updated to `from cap.v0.core import ...`.
- `skill.proto` enum values renamed: `SKILL_EXECUTION_*` →
  `SKILL_EXECUTION_STATUS_*` (resolves pre-existing buf lint
  ENUM_VALUE_PREFIX violation; wire-format unchanged because value
  numbers remain stable).
- `CONTRIBUTING.md` extended with DCO requirement + Domain Pack
  contribution workflow.

### Removed
- (none at this version — pre-release)

### Migration notes
- This is a **pre-public** release. No external consumers exist; the
  namespace reorganization is a single coordinated change without a
  deprecation window.

---

## [0.1.0] — Unreleased (Planned)

First public tag. To be cut once the autonomous backlog (A1-A10) lands and
user-action items (B1-B7) are complete. Will include:

- CAP-Core proto v0 (15 + mean_field message types)
- Construction Domain Pack v0
- Apache 2.0 LICENSE + NOTICE + SECURITY + CODE_OF_CONDUCT + GOVERNANCE
- mkdocs-material documentation site (EN + JA)
- PyPI / npm / Conan / BSR distribution
- Sigstore-signed wheels + CycloneDX SBOM + SLSA Build L3 attestation
- TLA+ formal models (TaskState / ReservationState / MachineMode /
  CAPCoordination) verified via TLC
