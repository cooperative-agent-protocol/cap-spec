<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-008: Versioning and Deprecation Policy

**Status:** Accepted
**Date:** 2026-05-26
**Context:** Pre-public-release (Phase 0)

## Decision

CAP adopts a **layered versioning model** that separates wire-format compatibility
(governed by the proto package name) from API maturity (governed by SemVer on
each published SDK / Domain Pack).

| Artifact | Versioning scheme | Backwards-compat policy |
|---|---|---|
| Proto package — Core | File-system encoded: `cap.v0.core`, `cap.v1.core`, ... | Within `v0` MAJOR: additive only (new fields / messages OK; remove / rename / type change NEVER). Wire-break = new major package `cap.v1.core`. |
| Proto package — Domain Pack | File-system encoded: `cap.v0.domains.<name>` | Same rules as Core. Domain Pack can independently advance to `cap.v1.domains.<name>` only when Core has advanced to `v1`. |
| Distribution packages | SemVer (`MAJOR.MINOR.PATCH`) per artifact | MAJOR bump = breaking API (Python / C++ / TS public API), MINOR = additive, PATCH = bug fix. Multiple SDKs (cap-sdk-core-python, cap-sdk-construction-python, ...) advance independently. |
| Conformance Levels | Discrete integer ascending (L1, L2, L3, ...) | A higher Level is a strict superset of the lower Levels. Adding a new Level is a MINOR. Removing or weakening a Level is a MAJOR. |
| RFCs | Sequential integer (RFC-0001, RFC-0002, ...) | Never deleted. Status field tracks lifecycle (`Final` / `Superseded`). |

## Context

CAP must remain stable enough for industrial OEMs to commit to long-term
integration while still being able to evolve the protocol as community feedback
arrives. The construction industry's adoption cycles are 5-10 years; we cannot
afford to break wire compatibility frequently. At the same time, SDK ergonomics
must be allowed to improve.

A single SemVer on the whole project (as gRPC initially did) conflates these two
concerns and creates pressure to either freeze prematurely or break OEMs late.
Separating them via the file-system-encoded proto package version is the
approach used by gRPC (`grpc.health.v1`), Google APIs (`google.cloud.vision.v1`),
and Buf-recommended layouts.

## Wire-format compatibility within a major proto package version

`cap.v0.core` (and `cap.v0.domains.<name>`) commits to:

1. **Never remove** a field, message, enum value, or RPC method.
2. **Never rename** any of the above (would change the protobuf descriptor name).
3. **Never change the wire type** of a field (e.g., `int32` → `int64` is forbidden
   even though the wire encoding is identical, because the descriptor changes).
4. **Never change the semantic meaning** of a field (e.g., reinterpreting an
   existing `int32 timeout = 5` from seconds to milliseconds is forbidden).
5. **Always additive**: new fields, messages, enum values, RPC methods OK.
6. **Always optional**: every new field must be safely ignorable by older
   readers (proto3 default semantics provide this automatically).

Anything in violation requires a new major proto package (`cap.v1.core`).

## SemVer for SDKs

Each published distribution package follows SemVer 2.0.0:

- **MAJOR**: incompatible API changes (e.g., renamed public method, removed
  argument, changed return type). Triggered by either:
  - a CAP Core / Domain Pack wire-break (forces SDK to follow), OR
  - an SDK-internal refactor that breaks user-facing API.
- **MINOR**: backwards-compatible additions (new methods, new optional args).
- **PATCH**: bug fixes that do not change documented behavior.

SDKs target the **latest Core minor** within a given Core major. Compatibility
between SDK versions and Core versions is documented in
[`docs/compatibility.md`](../compatibility.md) (compatibility matrix).

## Deprecation policy

When a field, message, RPC, or SDK API is marked for removal in a future
`cap.vN+1`:

1. Mark with `[deprecated = true]` in the proto file (proto3 annotation).
2. Add `[DEPRECATED]` prefix and a "removed in cap.vN+1" note to the field
   comment.
3. Generated SDKs emit a runtime warning when the deprecated field is used.
4. Announce in `CHANGELOG.md` of the affected repo, with the target removal
   version.
5. Minimum **2 minor releases** must elapse with the deprecation in place
   before the next major release that removes it.

## Conformance Level versioning

Conformance Levels are immutable once published. Adding a new test inside an
existing Level is a MINOR bump of `cap-conformance`; that test becomes
**advisory** until the next Conformance Level revision (typically annual). This
prevents existing certified implementations from losing their badge when a new
test lands.

A new Level (e.g., L4) is a MINOR `cap-conformance` bump.

Removing or relaxing a Level is treated as a MAJOR `cap-conformance` bump and is
discouraged; prefer adding a new Level with revised requirements.

## Compatibility matrix

[`docs/compatibility.md`](../compatibility.md) maintains a matrix of
`{cap-spec, cap-sdk-*, cap-conformance}` versions known to interoperate. Any
release that breaks an existing matrix cell is treated as a MAJOR bump.

## Rationale for file-system-encoded proto version

| Approach | Pros | Cons | Verdict |
|---|---|---|---|
| File-system `cap.v0`, `cap.v1`, ... | Two majors coexist in a single deployment. Existing readers untouched. | Imports get longer. | **Chosen** (gRPC-style) |
| Single `cap.*` + SemVer on wheel | One namespace. | Wire-break = wheel uninstall+reinstall, no coexistence. Cannot run two majors side-by-side. | Rejected |
| API versioning header on every RPC | Maximum flexibility. | Massive runtime overhead, hard to enforce. | Rejected |

## Consequences

- A wire-break (cap.v0 → cap.v1) is a **major coordinated effort** across all
  SDKs and the conformance suite. Expected cadence: at most once every 24
  months until v1.0, never after v1.0 without an exceptional motivation
  documented in a RFC.
- SDK MAJOR bumps are decoupled from proto majors; they can occur freely for
  ergonomic improvements within a stable wire major.
- The compatibility matrix must be a CI artifact, automatically updated and
  validated on every release tag.

## References

- gRPC versioning convention: <https://grpc.io/docs/what-is-grpc/core-concepts/#versioning>
- Buf's recommended layout: <https://buf.build/docs/best-practices/style-guide/>
- Google API versioning: <https://cloud.google.com/apis/design/versioning>
- SemVer 2.0.0: <https://semver.org/>
- ADR-002 (Transport-Neutral Semantics) — same wire-format must work across
  transports, reinforcing the importance of stable proto majors.
- ADR-011 (Domain Pack Architecture) — Domain Packs follow the same versioning
  rules independently.
