<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-012: `mean_field.proto` belongs in CAP-Core

**Status:** Accepted
**Date:** 2026-05-26
**Context:** Phase 0.3 Domain Pack reorganization — placement decision

## Decision

`cap.v0.core.mean_field` stays in CAP-Core (under `proto/cap/v0/core/`),
NOT in any Domain Pack. The schema is domain-agnostic at the math /
coordination layer; the construction-specific labels appearing in example
comments do not bind the schema to construction.

## Context

During the Phase 0.3 reorganization that split `cap.v0` into
`cap.v0.core` (universal) and `cap.v0.domains.<name>` (per-domain),
`mean_field.proto` required an explicit placement decision because:

- The file appeared during construction-domain development and its example
  comments reference construction agent types (`{"excavator": 1,
  "dump_truck": 2}`).
- The mean field control (MFC) / shadow-price / best-response vocabulary
  could be seen as a coordination layer (Core) or as a multi-machine
  fleet algorithm (potentially construction-only).
- An incorrect placement creates a wire-break later: moving from Core to
  Domain Pack (or vice versa) changes the proto package and forces every
  consumer to update imports.

## Analysis

### Schema content

`mean_field.proto` defines:

| Message | Purpose | Domain-coupling |
|---|---|---|
| `ZoneField` | `occupancy_by_type` as `map<string, int32>` over zones | Keys are abstract labels; values are agent counts. |
| `EdgeField` | Flow / congestion measurement on edges between zones | Pure graph-theoretic. |
| `ShadowPrices` | Lagrangian multipliers for resource constraints | Pure mathematical formulation. |
| `BestResponseRecord` | One iteration of best-response dynamics with payoff record | Generic game-theoretic record. |
| (other messages) | World snapshot for MFC iteration, equilibrium check | Generic. |

The `occupancy_by_type` map's **keys** ("excavator", "dump_truck") are
construction-specific Strings drawn from `cap.v0.core.MachineType`
enum-value names — those keys are deployment-resolved, not protocol-baked.
An agriculture deployment would use keys like "tractor", "harvester"
without any schema change.

The `BestResponseRecord.payoff` calculation, `ShadowPrices` interpretation,
and `EdgeField.congestion` semantics are domain-agnostic — they describe
how a coordinator computes equilibria over agents and resources, not what
kind of agents.

### Reuse across domains

Industrial fleet coordination problems where MFC applies:

- **Construction** (CAP v0): Multiple excavators sharing dump-truck access.
- **Agriculture** (future Domain Pack): Multiple tractors competing for
  refill-point access.
- **Mining**: Haul-truck dispatch in open-pit mines (well-studied MFC
  application).
- **Intralogistics**: AGV traffic in warehouse aisles (the canonical
  MFC example in robotics literature).
- **Port automation**: Container handlers around a single quay.

All five domains use the same `ZoneField` / `EdgeField` /
`ShadowPrices` / `BestResponseRecord` vocabulary unchanged. Promoting
these primitives into Core preserves the schema for every future Domain
Pack without coordination overhead.

### The alternative: keep in Construction Pack

If `mean_field.proto` were moved to `cap.v0.domains.construction`:

- Agriculture-future contributors would either duplicate the schema
  (forking) or import construction-domain types (wrong layering).
- A wire-break would be required to migrate to Core later.
- The optics — "CAP's coordination layer is construction-coupled" — would
  contradict the Cooperative Agent Protocol rebrand premise (ADR-011).

The cost of keeping `mean_field` in Core is exactly zero — Construction
Pack can populate `occupancy_by_type` with construction agent labels
without any schema accommodation. Future Domain Packs add their own
labels the same way.

## Decision boundary clarification

This ADR explicitly **does NOT** put any of the following into Core:

- The mapping `{"excavator": 1, "dump_truck": 2}` example labels in
  `mean_field.proto` comments. Those are illustrative; they are not in
  the wire format.
- Construction-specific MFC strategy implementations (best-response policy
  for excavator dispatch, etc.). Those live in the Machine Agent / Site
  Agent implementation layer, not in `cap-spec`.
- Per-domain congestion cost functions. Those are computed at the
  implementation layer using domain knowledge.

What is in Core:

- The wire schema for transmitting a mean-field snapshot.
- The wire schema for `ShadowPrices` and `BestResponseRecord`.
- The wire schema for `EdgeField` congestion measurements.

## Implementation requirement

The `mean_field.proto:118` example comment containing
`"降雨により視界不良"` (and any other Japanese / construction-specific
example string in proto comments) should be rephrased to use generic
descriptors in a follow-up commit. Comments are non-normative but should
not bias readers toward thinking the schema is construction-coupled.

A separate refactor task tracked in the backlog:

- Replace the `{"excavator": 1, "dump_truck": 2}` comment example with
  `{"agent_type_a": 1, "agent_type_b": 2}` or similar generic form, with
  a footnote pointing to the Domain-Pack-specific label set.

## Consequences

- `cap-spec/proto/cap/v0/core/mean_field.proto` stays in Core.
- Conformance Level 2+ implementations that claim MFC coordination must
  support `mean_field.proto` messages regardless of Domain Pack.
- Implementations that use the MFC vocabulary must document the
  Domain Pack labels they assume for `occupancy_by_type` keys.
- A future RFC may formalize `agent_type_uri` as a Domain-Pack-resolved
  reference type if multiple Domain Packs need stricter typing of keys.

## References

- ADR-011 (Domain Pack Architecture) — the rule "promote to Core when
  used by two or more domains" applied here preemptively.
- ADR-008 (Versioning) — explains why wire-break to move `mean_field`
  later is expensive enough to justify locking placement in Core now.
- Lasry, J.-M., Lions, P.-L. (2007). "Mean field games." Japanese
  Journal of Mathematics, 2: 229-260.
- Kizilkale, A. C., et al. (2019). "An integral control formulation of
  mean field game based large scale coordination." Automatica.
