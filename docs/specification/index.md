<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP Specification v0.1

**Cooperative Agent Protocol — Formal Specification**

*Construction Domain Pack v0 — reference domain*

Version: 0.1.0-draft
Date: 2026-03-19
Status: Draft

---

## Table of Contents

1. [Scope](ch01-scope.md)
2. [Terms and Definitions](ch02-terms.md)
3. [Architecture Overview](ch03-architecture.md)
4. [Communication Model](ch04-communication-model.md)
5. [Protocol Flows](ch05-protocol-flows.md)
6. [State Machines](ch06-state-machines.md)
7. [Message Reference](ch07-message-reference.md)
8. [Error Handling](ch08-error-handling.md)
9. [Security](ch09-security.md)
10. [Conformance](ch10-conformance.md)
11. [Implementation Guidelines](ch11-implementation-guidelines.md)

---

## Document Status

| Chapter | Status | Normative? |
|---------|--------|-----------|
| Ch 1: Scope | Complete | Informative |
| Ch 2: Terms and Definitions | Complete | Normative |
| Ch 3: Architecture Overview | Complete | Informative |
| Ch 4: Communication Model | Complete | Normative |
| Ch 5: Protocol Flows | Complete | Normative |
| Ch 6: State Machines | Complete | Normative |
| Ch 7: Message Reference | Complete | Normative |
| Ch 8: Error Handling | Complete | Normative |
| Ch 9: Security | Complete | Normative |
| Ch 10: Conformance | Complete | Normative |
| Ch 11: Implementation Guidelines | Complete | Informative |

---

## Related Documents

- [ADR-001: LLM Placement (Revised)](../adr/001-llm-site-agent-only.md)
- [ADR-002: Transport-Neutral Semantics](../adr/002-transport-neutral-semantics.md)
- [ADR-003: Independent Safety Channel](../adr/003-independent-safety-channel.md)
- [ADR-004: Entity Descriptor Representation](../adr/004-entity-representation.md)
- [ADR-005: Agent Dialogue Protocol](../adr/005-agent-dialogue-protocol.md)
- [ADR-006: Security Architecture](../adr/006-security-architecture.md)
- [Safety Boundary](../safety-boundary.md)

## Proto Source Files

- [`common.proto`](../../proto/cap/v0/common.proto) — Shared types and enums
- [`site_agent.proto`](../../proto/cap/v0/site_agent.proto) — Site → Machine messages
- [`machine_agent.proto`](../../proto/cap/v0/machine_agent.proto) — Machine → Site messages
- [`events.proto`](../../proto/cap/v0/events.proto) — Event messages
- [`error.proto`](../../proto/cap/v0/error.proto) — Error model
- [`entity.proto`](../../proto/cap/v0/entity.proto) — entity descriptors
- [`dialogue.proto`](../../proto/cap/v0/dialogue.proto) — Agent dialogue
- [`runtime.proto`](../../proto/cap/v0/runtime.proto) — CapFrame envelope and service

## Copyright

Copyright 2026 CAP Authors. Licensed under Apache-2.0.
