<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Compatibility Matrix

Pinned compatibility between published artifacts. Per
[ADR-008 — Versioning](adr/008-versioning.md), the proto package version
(`cap.v0.core`, `cap.v0.domains.construction`) governs wire compatibility,
and each distribution package independently follows SemVer.

This matrix is **maintained on every release**. CI runs the cross-product
of supported cells nightly (see
[`interop-matrix.yml`](https://github.com/cooperative-agent-protocol/cap-spec/blob/main/.github/workflows/interop-matrix.yml)).

## CAP Core ↔ SDK

| `cap-spec` Core | `cap-sdk-core-python` | `cap-sdk-core-cpp` | `@cap-protocol/sdk-core` | `cap-conformance` |
|---|---|---|---|---|
| v0.1.x | v0.1.x | v0.1.x (header-only) | v0.1.x | v0.1.x |
| v0.2.x | v0.1.x — v0.2.x | v0.1.x — v0.2.x (PImpl, ABI-versioned) | v0.1.x — v0.2.x | v0.1.x — v0.2.x |

Backwards-compatibility rule: an SDK published against Core `v0.N` works
against any `v0.M` where `M >= N` (additive only within a major). When
Core advances to `cap.v1.core`, SDKs must publish a new MAJOR.

## Construction Domain Pack ↔ SDK

| `cap-spec` Construction | `cap-sdk-construction-python` | `cap-sdk-construction-cpp` | `@cap-protocol/sdk-construction` |
|---|---|---|---|
| v0.1.x | v0.1.x | v0.1.x | v0.1.x |

Domain Pack version evolves independently of Core. A Construction Pack
v0.3 may depend on Core v0.1 or v0.2.

## Conformance suite ↔ SDK

| `cap-conformance` | `cap-sdk-core-python` | `cap-sdk-core-cpp` |
|---|---|---|
| v0.1.x | v0.1.x | v0.1.x (header-only) |

Conformance Levels (Core L1 / L2 / L3) are immutable within a published
release. Adding a new test inside an existing Level is a MINOR bump; the
test is advisory until the next Level revision. See
[ADR-008](adr/008-versioning.md) for the rule.

## Toolchain pins

| Tool | Pinned version | Note |
|---|---|---|
| `buf` CLI | 1.69.0 | Used by all generators + CI |
| `protobuf` (Python runtime) | >= 7.35.0 | Required by BSR-generated `*_pb2.py` |
| `grpcio` (Python) | >= 1.70.0 | LTS line per ADR-008 |
| `grpcio-tools` (Python codegen) | >= 1.81.0rc1 | Pre-release until 1.81 stable lands |
| `gRPC` C++ (via Conan) | 1.62 LTS + 1.66 | CI matrix runs both |
| C++ standard | C++17 minimum | per [ADR-011](adr/011-domain-pack-architecture.md) |
| Node | 20 LTS | TS SDK only |
| TLA+ Tools | 1.8.0 (`tla2tools.jar`) | Formal verification |

## Domain Pack registry

| Pack | Status | Maintainer | Latest |
|---|---|---|---|
| `cap.v0.domains.construction` | Released | CAP project | v0.1.x |
| `cap.v0.domains.agriculture` | Planned | _contributor wanted_ | — |
| `cap.v0.domains.mining` | Planned | _contributor wanted_ | — |
| `cap.v0.domains.forestry` | Planned | _contributor wanted_ | — |
| `cap.v0.domains.intralogistics` | Planned | _contributor wanted_ | — |

## How to update this matrix

This file is updated as part of every `cap-spec` release. When a new
SDK release lands, the SDK maintainer opens a PR adding/updating the
relevant row. CI rejects PRs that introduce a wire-incompatible change
without also updating this matrix.
