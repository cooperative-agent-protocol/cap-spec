<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ISO 11783 (ISOBUS) ↔ CAP — Future Mapping (Placeholder)

> **Status: placeholder.** This document will be authored alongside the
> Agriculture Domain Pack proposal. Until then it serves as a reservation
> of the file path and a brief sketch of intended scope.

## ISO 11783 overview

ISO 11783 (commonly known as **ISOBUS**) is the dominant wire-level
protocol for agricultural tractor / implement communication in fields:

- ISO 11783-3 — Data link layer
- ISO 11783-7 — Implement messages application layer
- ISO 11783-10 — Task controller and management information system data
  interchange
- ISO 11783-13 — File server
- (additional parts cover network management, virtual terminal, etc.)

Major Japanese agricultural OEMs (Kubota, Yanmar, Iseki) participate in
ISO TC23/SC19 working groups. ISOBUS is regulated through AEF
(Agricultural Industry Electronics Foundation) certification.

## CAP relationship

CAP sits at the **task coordination** layer above ISOBUS:

```
LLM-based Site Agent (CAP — orchestrates multiple tractors)
   ↓ CAP WorkOrder
Machine Agent (CAP — interprets task, advisory LLM)
   ↓ HAL abstraction
Tractor + Implement (ISOBUS — sensor/actuator control)
```

A future `cap-bridge-isobus` integration component (community-maintained
when the Agriculture Domain Pack lands) will translate between the CAP
HAL abstraction and ISO 11783-7 / ISO 11783-10 messages.

## What an Agriculture Domain Pack RFC must cover

The future RFC (using the [Domain Pack template](../rfcs/domain-pack-template.md))
must address:

1. **Skill catalog**:
   `agriculture.plow`, `agriculture.plant`, `agriculture.spray`,
   `agriculture.harvest`, `agriculture.fertilize`, ...
2. **Zone types**: `field`, `headland`, `refill_point`, `boundary_line`,
   `obstacle_marker`, `gate`.
3. **Equipment subtypes**: tractor (4WD / track-laying), harvester (combine /
   forage / sugar-beet), sprayer (self-propelled / trailed), seeder,
   fertilizer spreader.
4. **ISOBUS bridge contract**: which ISO 11783-7 PGNs map to CAP
   `WorkOrder` / `ProgressEvent` / `ObservationFrame` fields.
5. **Regulatory considerations**: pesticide / fertilizer application
   logging requirements; field-level GNSS RTK reliance; safety modes
   adjacent to roads.

## References

- ISO 11783 family of standards.
- AEF (Agricultural Industry Electronics Foundation) Certification:
  <https://www.aef-online.org/>
- VDA Recommendation 5050 — adjacent (intralogistics / AGV), shares the
  "central master coordinates multiple machines" pattern.
- [ADR-011](adr/011-domain-pack-architecture.md) — Domain Pack
  architecture.
- [Domain Pack RFC template](../rfcs/domain-pack-template.md).
