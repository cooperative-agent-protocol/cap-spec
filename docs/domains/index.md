<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Domain Packs

CAP Core is **domain-agnostic**. Industrial domain specifics — skill names,
zone types, equipment subtypes — are organized as **Domain Packs**, each in
its own proto namespace (`cap.v0.domains.<name>`) and conformance suite
(`cap-conformance/domains/<name>/`).

See [ADR-011 — Domain Pack Architecture](../adr/011-domain-pack-architecture.md) for the formal Core / Domain Pack
boundary and the rules for proposing new Packs.

| Domain Pack | Status | Maintainer | RFC |
|---|---|---|---|
| [Construction](construction/index.md) | **v0 — reference Pack** | CAP project | n/a (v0 reference) |
| [Agriculture](agriculture/index.md) | Planned | _open — contributor wanted_ | TBD |
| [Mining](mining/index.md) | Planned | _open — contributor wanted_ | TBD |
| [Forestry](forestry/index.md) | Planned | _open — contributor wanted_ | TBD |
| [Intralogistics](intralogistics/index.md) | Planned | _open — contributor wanted_ | TBD |

## Proposing a new Domain Pack

Use the [Domain Pack RFC template](../../rfcs/domain-pack-template.md). The
proposal must cover:

- Pack name + skill namespace prefix
- Target equipment classes
- Existing standards alignment (ISO TC23 for agriculture, ISO TC82 for
  mining, etc.)
- Reference implementation commitment (12+ months)

## Third-party extensions

Organizations that need domain-specific extensions without going through
the official RFC can publish under the `cap.v0.extensions.<org>.<name>`
namespace. These do not receive an official conformance badge but interop
on the wire with Core.
