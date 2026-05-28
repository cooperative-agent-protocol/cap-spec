<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP — Cooperative Agent Protocol

> **For industrial machine coordination. Construction-first.**

CAP is an open protocol for orchestrating LLM-driven multi-machine fleets in
industrial environments. The protocol's core (`cap.v0.core`) is
domain-agnostic — the same coordination primitives serve construction sites,
agricultural fields, mining operations, and warehouse intralogistics. Each
industrial domain is expressed as a **Domain Pack** layered on top of Core.

The v0.x reference Domain Pack is **Construction**.

## Why CAP

| Need | What CAP provides |
|---|---|
| Coordinate multiple autonomous / semi-autonomous machines | `WorkOrder` / `ProgressEvent` task lifecycle (Ch06, Ch07) |
| Layer LLMs into the loop without breaking safety guarantees | 3-layer architecture: Site Agent (LLM) → Machine Agent (advisory LLM) → Safety Supervisor (deterministic) (ADR-001 / ADR-003) |
| Talk natural-language between agents | `AgentDialogue` (ADR-005) |
| Resolve resource conflicts between machines | Reservation protocol + handover (Ch06) |
| Express tasks and zones in human-readable terms | Abstract Language Objects (ALO) (ADR-004) |
| Prove correctness of coordination state machines | TLA+ formal models (ADR-007) |
| Plug new domains in without forking | Domain Pack architecture (ADR-011) |

## What CAP is **not**

- **A controller**: CAP does not directly drive actuators. Implementations
  use a HAL abstraction below Machine Agent.
- **A safety certification** (SIL / PL / ASIL): the Safety Supervisor sits
  on an independent channel; CAP is **out-of-scope** for functional safety
  cert (ADR-003).
- **A replacement for OPC UA or ISO 15143-3**: CAP operates at a higher
  task / dialogue layer and is **complementary** (ADR-009).

## Start here

1. [Specification — Chapter 1: Scope](specification/ch01-scope.md) — what CAP
   covers and what it does not.
2. [Domain Packs — Construction (v0)](domains/construction/index.md) — the
   first reference Domain Pack.
3. [Quickstart](#quickstart) — clone, run, send a `WorkOrder` in five minutes.
4. [Conformance](specification/ch10-conformance.md) — Levels 1 / 2 / 3 + Domain
   Pack extensions.

## Quickstart

```bash
# Clone the reference implementation
git clone https://github.com/cooperative-agent-protocol/cap-reference.git
cd cap-reference/examples/quickstart

# Spin up: Site Agent + 2 Machine Agents + MQTT broker
docker-compose up
```

Connect your own Machine Agent via the published proto module:

```bash
# Python
pip install cap-proto-core-python cap-sdk-core-python

# C++
conan install --requires=cap-sdk-core-cpp/0.1.0

# TypeScript
npm install @cap-protocol/core @cap-protocol/sdk-core
```

## Standards alignment

CAP is designed to coexist with existing industrial standards:

- **ISO 15143-3** (Worksite topographical data exchange) — see the
  [mapping doc](iso-15143-3-mapping.md).
- **OPC UA Companion Specification for Construction** — see [ADR-009](adr/009-opcua-relation.md).
- **VDA 5050** (AGV interop) — design inspiration for the interop event
  format (post-v1.0).
- **ISO 11783 (ISOBUS)** — future Agriculture Domain Pack alignment.

## Project governance

- **License**: [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
- **Contribution**: signed off under [DCO](https://developercertificate.org/) — see [Contributing](https://github.com/cooperative-agent-protocol/cap-spec/blob/main/CONTRIBUTING.md).
- **Code of Conduct**: [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
- **Security**: see [SECURITY.md](https://github.com/cooperative-agent-protocol/cap-spec/blob/main/SECURITY.md).
- **Trademark**: "Cooperative Agent Protocol" / "CAP" — pending JPO
  registration. See [TRADEMARK_POLICY.md](https://github.com/cooperative-agent-protocol/cap-spec/blob/main/TRADEMARK_POLICY.md).

## Origin

CAP began as research at The University of Tokyo, Department of Civil
Engineering, Construction Mechanization Laboratory. The v0 Construction
Domain Pack is informed by that research; Agriculture / Mining / Forestry /
Intralogistics Domain Packs welcome contributors via the
[RFC process](rfcs/README.md).
