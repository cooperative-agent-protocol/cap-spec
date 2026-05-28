<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-009: Relationship to OPC UA and OPC UA Companion Specification for Construction

**Status:** Accepted
**Date:** 2026-05-26
**Context:** Pre-public-release (Phase 0) — Standards-body positioning

## Decision

CAP positions itself as **complementary** to OPC UA. CAP operates at a higher
semantic layer (LLM-driven task orchestration with state machines and dialogue)
while OPC UA operates at a lower-level (industrial data exchange, machine
telemetry). Bridging between CAP and OPC UA is left to the implementation layer
(e.g., a `cap-bridge-opcua` integration component); the CAP specification does
not depend on OPC UA and vice versa.

## Context

OPC UA (IEC 62541) is the dominant industrial automation protocol in
manufacturing and increasingly in mobile machinery. Major construction-equipment
OEMs already participate in OPC UA standardization:

- VDMA Construction Equipment & Building Material Machinery is drafting an
  **OPC UA Companion Specification for Construction Equipment** (in committee as
  of 2026).
- Komatsu, Caterpillar, Volvo CE, Liebherr have varying levels of OPC UA
  alignment.
- ISO 15143-3 (worksite topographical data exchange) is already harmonized
  with OPC UA in some implementations.

CAP's release strategy must explicitly position itself relative to OPC UA so
that adopters understand what overlap exists and what does not.

## Comparison

| Aspect | OPC UA | CAP |
|---|---|---|
| Layer | Industrial data exchange (information model + transport) | Task-level multi-agent coordination |
| Scope | Sensor / actuator / control-system telemetry | Site Agent ↔ Machine Agent task orchestration |
| Architecture | Client / server, pub-sub, address space | Site Agent ↔ Machine Agent ↔ Safety Supervisor (3-layer) |
| Transport | OPC UA TCP / HTTPS / MQTT | gRPC / MQTT / WebSocket (transport-neutral via ADR-002) |
| Information model | Rich type system, address space, references | Proto3 messages + state machines |
| Sessions / discovery | Built-in | Out of scope (use service discovery layer) |
| LLM integration | None (data plane) | First-class (Site Agent, Machine Agent advisory) |
| Safety | Various safety profiles (OPC UA Safety) | Independent safety supervisor channel (ADR-003) |
| Formal verification | Some published work | TLA+ models with TLC verification (ADR-007) |
| Conformance | Compliance Test Tool (CTT) | cap-conformance Level 1/2/3 |
| Domain coverage | Many Companion Specs across industries | Domain Packs (Construction v0, Agriculture / Mining / Forestry / Intralogistics future) |

CAP and OPC UA address **different problems**. OPC UA standardizes how machines
report state and accept low-level commands; CAP standardizes how LLM-driven
agents orchestrate task-level work between machines.

## Integration pattern

A site running both CAP and OPC UA typically has:

```
                     ┌──────────────────────────────────┐
                     │      LLM-based Site Agent        │
                     │   (CAP — task orchestration)     │
                     └──────────┬───────────────────────┘
                                │ CAP WorkOrder
                                ▼
   ┌──────────────────────────────────────────────────────┐
   │              Machine Agent (CAP)                     │
   │   - Task interpretation, advisory LLM                │
   │   - Receives WorkOrder, emits ProgressEvent          │
   └──────────┬───────────────────────────────────────────┘
              │ Internal: HAL abstraction
              ▼
   ┌──────────────────────────────────────────────────────┐
   │   Machine vendor stack (proprietary or OPC UA)       │
   │   - Telemetry, actuator I/O                          │
   │   - OPC UA Companion Spec for Construction (if avail)│
   └──────────────────────────────────────────────────────┘
```

A `cap-bridge-opcua` component (out of CAP spec scope) can translate between the
CAP HAL abstraction and an OPC UA address space, allowing CAP-compliant Machine
Agents to drive OPC UA-equipped machines without either side knowing about the
other.

## Standards alignment

| OPC UA artifact | CAP alignment |
|---|---|
| OPC UA Companion Specification for Construction (in draft) | CAP will publish a mapping document showing how OPC UA nodes correspond to CAP `Manifest` / `Heartbeat` fields once the Companion Spec stabilizes. |
| OPC UA Safety | CAP's independent safety supervisor channel (ADR-003) is the SIL-relevant layer. OPC UA Safety can coexist as the lower-level transport for that channel. |
| OPC UA Pub-Sub over MQTT | CAP's MQTT transport profile (ADR-002) can coexist on the same broker without interference. |
| ISO 15143-3 | CAP-Construction Domain Pack will include an ISO 15143-3 mapping (separate document, `docs/iso-15143-3-mapping.md`). |

## Rationale

- **Avoid territory disputes**: CAP and OPC UA solve different problems. The
  default community reaction to a "new protocol" is "why not extend OPC UA?".
  A clear positioning document answers this preemptively.
- **OEM dual-stack support**: most major OEMs already have OPC UA roadmaps.
  Forcing them to choose discourages adoption; coexistence enables it.
- **Liaison readiness**: ISO TC127 and OPC Foundation may eventually request a
  formal liaison. This ADR is the basis for that request.

## Consequences

- The CAP specification must not depend on any OPC UA construct.
- Reference SDK implementations must not require OPC UA libraries.
- Future work: publish `docs/opcua-bridge-pattern.md` once a reference bridge
  implementation exists.
- A separate `cap-bridge-opcua` repository may eventually live under the CAP
  GitHub org as a community-contributed integration, but is not in scope for
  v0.x release.

## References

- IEC 62541 (OPC UA family of standards)
- VDMA Construction Equipment & Building Material Machinery — OPC UA Companion
  Specification for Construction Equipment (in draft)
- ISO 15143-3 — Worksite topographical data exchange
- ADR-002 (Transport-Neutral Semantics)
- ADR-003 (Independent Safety Channel)
