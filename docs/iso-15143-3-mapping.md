<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ISO 15143-3 ↔ CAP Mapping

> **Status: draft skeleton.** This document maps fields between ISO 15143-3
> (Earth-moving machinery and mobile road construction machinery — Worksite
> data exchange) and CAP-Core + CAP Construction Domain Pack. It will be
> elaborated as part of the standards-alignment outreach (see plan
> Phase E1-E3).

## ISO 15143-3 overview

ISO 15143-3 (also known as **AEMP 2.0**, the legacy industry name from the
Association of Equipment Manufacturers) defines a telematics data exchange
schema for construction equipment. Major OEMs (Komatsu, Caterpillar, Volvo
CE, Hitachi CM, Liebherr) publish telematics under variants of this schema.

ISO 15143-3 sits at the **machine telematics** layer. CAP sits at the
**task-level coordination** layer. They are complementary; this mapping
shows how a CAP-conformant Machine Agent can ingest an ISO 15143-3 feed and
expose the relevant fields via the CAP `Heartbeat` / `Manifest` / ALO
messages.

## Field correspondence (high-level)

| ISO 15143-3 | CAP message | CAP field |
|---|---|---|
| `Equipment.Identification.SerialNumber` | `CapabilityManifest` | `machine_id` (deployment-resolved) |
| `Equipment.Identification.MakeAndModel` | `CapabilityManifest` | `machine_type` (enum from `cap.v0.core.common.MachineType`) + `hal_profile` |
| `Equipment.Location.{Latitude,Longitude,Altitude}` | `Heartbeat` / `ObservationFrame` | Position / pose fields (transport via dedicated pose stream, not raw heartbeat) |
| `Equipment.CumulativeOperatingHours` | `CapabilityManifest` / `Heartbeat` | `software_version` + custom telemetry (not modeled in v0; Domain Pack extension candidate) |
| `Equipment.FuelUsed.PeriodFuelUsed` | `Heartbeat` | `fuel_or_battery_percent` (current level, not cumulative) |
| `Equipment.FuelRemaining.Percent` | `Heartbeat` | `fuel_or_battery_percent` |
| `Equipment.MachineState` | `Heartbeat` | `current_mode` (CAP MachineMode enum) + `healthy` |
| `Equipment.EngineState` | (not modeled in CAP v0) | Domain Pack extension candidate |
| `Equipment.WorkSiteIdentifier` | `CapabilityManifest` | (via reservation context, not in Manifest v0) — Domain Pack extension candidate |

## Mapping completeness

The above table is **partial**. A complete v1.0 mapping document will:

1. Cover every ISO 15143-3 schema field with one of:
   - Direct CAP field correspondence
   - Domain Pack extension placeholder
   - Out-of-scope marker (with rationale)
2. Document the **inverse direction** — for fields ISO 15143-3 lacks that
   CAP relies on (task lifecycle, dialogue, formal task state machine).
3. Include reference adapter code (`cap-bridge-aemp` planned package).

## Adapter strategy

A `cap-bridge-aemp` integration component (out of `cap-spec` scope; planned
post-v1.0 community repo) will offer:

- **AEMP → CAP**: poll an OEM's AEMP 2.0 endpoint, transform records into
  `Heartbeat` + `ObservationFrame` messages, push into a CAP runtime.
- **CAP → AEMP**: serve a read-only AEMP 2.0 endpoint backed by aggregated
  CAP telemetry, for sites that need to expose CAP-coordinated fleets to
  existing AEMP-aware dashboards.

## Liaison status

- **JCMA** (日本建設機械施工協会) — primary outreach (planned via 全先生 network).
- **JISC** (日本産業標準調査会) — liaison inquiry path to ISO TC127/SC3.
- **ISO TC127/SC3** — formal liaison after at least one OEM co-sponsors.

## References

- ISO 15143-3:2020 — Earth-moving machinery and mobile road construction
  machinery — Worksite data exchange — Part 3: Worksite topographical data.
- AEM/AEMP Telematics Data Standard 2.0 (industry-led predecessor).
- [ADR-009](adr/009-opcua-relation.md) — Relationship to OPC UA (similar
  positioning narrative).
- [ADR-011](adr/011-domain-pack-architecture.md) — Domain Pack architecture;
  ISO 15143-3 alignment is a Construction Domain Pack concern.
