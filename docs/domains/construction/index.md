<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Construction Domain Pack (v0)

The Construction Domain Pack is the **v0 reference** for CAP. It defines
construction-specific skills, zone types, and equipment subtypes layered
on top of CAP Core.

## Proto schemas

| File | Contents |
|---|---|
| `cap.v0.domains.construction.skills` | `construction.excavate_batch`, `construction.haul_route`, `construction.dump` + parameter messages + effect-key enums |
| `cap.v0.domains.construction.intent` | Construction-specific fine-grained intent payloads carried by `cap.v0.core.Intent.domain_intent` |
| `cap.v0.domains.construction.zones` | `excavation` / `dump` / `haul_road` / `terrain` / `staging` zone types + soil-class enum + per-type attribute messages |
| `cap.v0.domains.construction.equipment` | Excavator / Hauler / Dozer / Roller / Grader / Loader / Crane subtype enums + attribute messages |

Source: [`cap-spec/proto/cap/v0/domains/construction/`](https://github.com/cooperative-agent-protocol/cap-spec/tree/main/proto/cap/v0/domains/construction)

## Distribution

| Layer | Python | TypeScript | C++ |
|---|---|---|---|
| Proto bindings | `cap-proto-construction-python` | `@cap-protocol/construction` | `cap_proto_construction_cpp` (Conan / vcpkg) |
| SDK | `cap-sdk-construction-python` | `@cap-protocol/sdk-construction` | `cap_sdk_construction_cpp` |

## Conformance

Construction conformance tests live in `cap-conformance/domains/construction/`
(post-A4 reorganization). Run with:

```bash
pytest cap-conformance --target grpc://localhost:50051 --domain construction
```

A conformant Construction implementation supports the bundled scenarios:

- `scn_excavate_basic_01.yaml` — single-excavator happy path
- `scn_excavate_underyield_01.yaml` — L7 verification failure
- `scn_terrain_too_steep_01.yaml` — L3 precondition refusal
- `scn_haul_basic_01.yaml` — single-truck happy path
- `scn_truck_wrong_position_01.yaml` — L3 pose precondition refusal
- `scn_excavate_haul_chain_01.yaml` — multi-machine chain coordination

## Standards alignment

- **ISO 15143-3** (Worksite topographical data exchange) — mapping doc in
  the [Standards Alignment section](../../iso-15143-3-mapping.md).
- **ISO 17757** (Autonomous and semi-autonomous machine system safety) —
  CAP's independent safety channel (ADR-003) sits in the ISO 17757 boundary.
- **ISO 19014** (Functional safety) — CAP itself is **out-of-scope** for
  SIL/PL/ASIL; the Safety Supervisor sits outside CAP.
- **JCMA** (Japan Construction Mechanization Association) — primary
  outreach body, planned interop event in M3 (see project planning).

## Stability

Construction Domain Pack v0.x is **pre-1.0 and additive**. Skill names,
zone types, and equipment subtypes will not be renamed within v0.x. New
items (additional skills, additional zone types) are MINOR bumps.
A wire-incompatible change moves to `cap.v1.domains.construction` per
[ADR-008](../../adr/008-versioning.md).
