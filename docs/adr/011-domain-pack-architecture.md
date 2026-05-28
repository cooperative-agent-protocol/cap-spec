<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-011: Domain Pack Architecture

**Status:** Accepted
**Date:** 2026-05-26
**Context:** Pre-public-release (Phase 0) — CAP rebrand to Cooperative Agent Protocol

## Decision

CAP is partitioned into two layers:

1. **CAP-Core** — domain-agnostic primitives (Manifest, Heartbeat, WorkOrder,
   Lifecycle, Dialogue, ALO, Frame, Safety Supervisor contract, 3-Layer
   Architecture) shared across every industrial domain.
2. **CAP Domain Packs** — domain-specific extensions defining skills, zone
   types, equipment classes, and conformance suites for one industrial domain.

The v0.x reference Domain Pack is **Construction**. Additional Domain Packs
(Agriculture, Mining, Forestry, Intralogistics) may be contributed through the
RFC process (see [`rfcs/domain-pack-template.md`](../../rfcs/domain-pack-template.md)).

## Context

The CAP rename from "Construction Agent Protocol" to "Cooperative Agent
Protocol" reflects an observation about the underlying design: the core
primitives — task assignment, lifecycle management, dialogue, safety supervisor
boundary — are independent of the equipment class being coordinated. Excavators
on a construction site and tractors in a field have the same coordination needs
at the protocol layer; what differs is the skill vocabulary (`excavate_batch`
vs `plow`), zone semantics (`excavation` vs `field`), and equipment attributes.

A monolithic specification that hard-codes construction terms in the Core would:

- Force agriculture / mining / forestry contributors to fork or reinterpret.
- Inflate the conformance surface (most construction-specific tests are
  irrelevant in agriculture).
- Make the spec less defensible at standards bodies covering other domains
  (ISO TC23, ISO TC82, etc.).

The Domain Pack architecture solves these problems while keeping the bar to
contribute a new domain low (only a small set of proto files + an SDK module
+ a conformance test set).

## Boundary

### What lives in Core

- Manifest, Heartbeat, WorkOrder, WorkOrderAck, ProgressEvent
- Lifecycle, Intent, PlanContractWire, TrajectoryRequest, VelocityCommand
- Frame, CapFrame, transport profiles
- AgentDialogue, DialogueIntent, SituationReport, LocalDecision, PlanProposal
- ALODescriptor, ALOManager, ALOProperty, ALOInteraction, ALOStateUpdate
- WorldDelta, ZoneConstraintGridDelta (without domain-specific zone types),
  ObservationFrame
- AbortCause (generic causes only — slope, clearance, hazard intrusion etc.;
  no construction-only causes)
- MachineSpec, BodyGeometry, MobilityGeometry, MobilityLimits, CycleTimings
- MachineBridgeConfig
- Generic MachineType enum (excavator, dump_truck, dozer, grader, loader,
  roller, crane — construction-leaning but commonly understood; carrier is the
  intentionally-generic catch-all)
- Error / CapError / ErrorDomain (generic categories)
- Safety Supervisor contract (Layer [C])

The Core proto package is `cap.v0.core`.

### What lives in Domain Packs

- Skill definitions (e.g. `construction.excavate_batch`, `agriculture.plow`)
  with their preconditions, expected_effects, and parameters
- Zone types beyond the generic primitives (e.g. construction.excavation_zone,
  agriculture.headland, mining.drill_pad)
- Equipment subtypes within a generic class (e.g. agriculture.row_crop_tractor,
  forestry.harvester_head)
- Domain-specific failure labels (e.g. agriculture-only L9_SOIL_TYPE_MISMATCH)
- Domain-specific HAL hints (e.g. tractor PTO control, sprayer nozzle control)
- Conformance suites for the domain's skill / zone / equipment semantics

The Construction Domain Pack proto package is
`cap.v0.domains.construction`.

### Gray-area rule

If a concept is **used by exactly one domain today**, it goes in that Domain
Pack. If it generalizes to **two or more domains**, it is promoted to Core via
RFC. Promotion is a wire-break for Core (cap.v1) unless the field can be added
additively.

## File-system layout

```
cap-spec/proto/cap/v0/
├── core/
│   ├── common.proto
│   ├── runtime.proto
│   ├── machine_agent.proto
│   ├── site_agent.proto
│   ├── lifecycle.proto
│   ├── intent.proto
│   ├── world_model.proto
│   ├── events.proto
│   ├── alo.proto
│   ├── dialogue.proto
│   ├── error.proto
│   ├── skill.proto
│   ├── machine_spec.proto
│   ├── machine_bridge_config.proto
│   └── control.proto
└── domains/
    ├── construction/
    │   ├── skills.proto
    │   ├── zones.proto
    │   └── equipment.proto
    ├── agriculture/         (future)
    ├── mining/              (future)
    ├── forestry/            (future)
    └── intralogistics/      (future)
```

Each Domain Pack has its own `buf.yaml` module name:

- `buf.build/cap-protocol/cap-core`
- `buf.build/cap-protocol/cap-construction`
- `buf.build/cap-protocol/cap-agriculture` (future)
- ...

## Distribution

| Layer | Python | TypeScript | C++ |
|---|---|---|---|
| Core proto | `cap-proto-core-python` | `@cap-protocol/core` | `cap_proto_core_cpp` (Conan / vcpkg) |
| Construction proto | `cap-proto-construction-python` | `@cap-protocol/construction` | `cap_proto_construction_cpp` |
| Core SDK | `cap-sdk-core-python` | `@cap-protocol/sdk-core` | `cap_sdk_core_cpp` |
| Construction SDK | `cap-sdk-construction-python` | `@cap-protocol/sdk-construction` | `cap_sdk_construction_cpp` |

Domain Pack packages depend on the corresponding Core package at a compatible
SemVer range. They are independently versioned (a Construction Pack v0.3 may
depend on Core v0.1 or v0.2).

## Skill namespacing

Skill names are dotted, with the Domain Pack prefix:

```
construction.excavate_batch
construction.haul_route
construction.dump
agriculture.plow
agriculture.harvest
mining.drill
forestry.fell
intralogistics.transport
```

The Core does **not** define any concrete skill — only the
`SkillDefinition` / `SkillManifest` / `SkillRegistry` abstractions.

## Conformance

Two-tier conformance:

| Tier | Test set | Mandatory? |
|---|---|---|
| Core Level 1/2/3 | `cap-conformance/core/` | Yes for every conformant impl |
| Domain Pack conformance | `cap-conformance/domains/<name>/` | Only if the impl claims that Domain Pack |

```bash
# Run only Core conformance
pytest cap-conformance --target grpc://localhost:50051

# Run Core + Construction Domain Pack conformance
pytest cap-conformance --target grpc://localhost:50051 --domain construction
```

Conformance certification badges combine both tiers:

- "CAP Core Conformant L2"
- "CAP Construction Domain Pack Conformant" (implies Core L1 at minimum)

## Governance

| Decision | Authority |
|---|---|
| Core changes | CAP steering committee (initially the BDFL) |
| New Domain Pack approval | CAP steering committee, via RFC |
| Domain Pack changes within an approved Pack | Pack maintainer(s), with announcement to the broader community |
| Promotion of a concept from Domain Pack → Core | RFC (typically a major bump of `cap.vN+1`) |

Domain Pack maintainers must:

- Maintain a public reference implementation for at least 12 months.
- Respond to security issues within 30 days.
- Keep the conformance suite green on every release.
- Coordinate with Core maintainers on namespace and field-number allocation.

A Pack that becomes unmaintained may be marked `Status: Dormant` (not removed
from the spec, but the conformance suite excluded from CI). Restoring an
implementation reactivates the Pack.

## Third-party extensions

Organizations may publish their own extensions without going through the RFC
process by using a **third-party namespace**:

```
cap.v0.extensions.<org-id>.<pack-name>
```

These are not part of the CAP specification, do not receive an official badge,
and the org bears full responsibility for maintenance and compatibility.
Promoting a third-party extension to an official Domain Pack requires going
through the RFC process and demonstrating community uptake.

## Rationale

- **Construction-first development is preserved**: the user's research focus
  remains in `cap.v0.domains.construction`, and changes there do not affect
  third-party Domain Pack maintainers.
- **Future contributors have a clear contract**: a single template
  (`rfcs/domain-pack-template.md`) explains exactly what's required.
- **Standards body alignment becomes per-domain**: ISO TC127 binds to
  Construction Pack, ISO TC23 to Agriculture Pack, ISO TC82 to Mining Pack,
  VDA 5050 / ISO TC110 to Intralogistics. CAP Core stays neutral and
  liaison-ready for all of them.
- **Conformance is composable**: a vendor can claim Core L3 without committing
  to any specific Domain Pack, and add Domain Pack conformance as their
  business expands.

## Consequences

- The Phase 0 namespace reorganization moves existing proto files from
  `cap/v0/` to `cap/v0/core/` and creates `cap/v0/domains/construction/`. This
  is a single coordinated change executed before public release; no migration
  path is needed because there are no external consumers yet.
- Conformance tests are sorted into `cap-conformance/core/` and
  `cap-conformance/domains/construction/`.
- The reference SDK adopts the same partition (`cap_sdk_core` and
  `cap_sdk_construction`).
- The compatibility matrix (ADR-008, `docs/compatibility.md`) gains an extra
  axis: `{Core version, Domain Pack name, Domain Pack version}`.
- Documentation site (Phase C) navigates by "Core spec" and "Domain Packs" as
  top-level sections.

## References

- ADR-008 (Versioning) — independent versioning of Core and Domain Packs.
- ADR-002 (Transport-Neutral Semantics) — transport profile is Core-only.
- ADR-003 (Independent Safety Channel) — Safety Supervisor contract is Core.
- ADR-004 (ALO Representation) — ALO is Core.
- `rfcs/domain-pack-template.md` — template for proposing new Domain Packs.
- ISO TC127 (Earth-moving machinery) — Construction Domain Pack alignment.
- ISO TC23 (Tractors and machinery for agriculture and forestry) — future
  Agriculture / Forestry Domain Pack alignment.
- ISO 11783 (Tractors and machinery for agriculture and forestry — Serial
  control and communications data network, "ISOBUS") — coexistence pattern
  for future Agriculture Pack.
- VDA 5050 (Interface for AGV) — coexistence pattern for future
  Intralogistics Pack.
