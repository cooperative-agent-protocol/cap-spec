<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP vs MCP: Complementary, Not Competing

## Overview

**CAP** (Cooperative Agent Protocol) and **MCP** (Model Context Protocol) operate at
different layers of the AI agent stack. They are **complementary**, not competing
standards.

| | MCP | CAP |
|---|---|---|
| **Layer** | LLM ↔ Tool interface | Multi-machine industrial fleet coordination |
| **Scope** | How an LLM calls external tools/resources | How a Site Agent orchestrates Machine Agents with safety, coordination, and auditability |
| **Transport** | stdio, Streamable HTTP | gRPC, MQTT, WebSocket (transport-neutral) |
| **State management** | Stateless tool calls | Explicit state machines (TaskState, MachineMode, ReservationState, HandoverFlow, DialogueFlow) |
| **Safety** | Not addressed | Independent safety supervisor channel (ADR-003) |
| **Multi-agent** | Not addressed | Reservation protocol, deadlock prevention, handover negotiation |
| **Formal verification** | None | TLA+ models with TLC-verified safety/liveness properties |

## Where MCP Ends and CAP Begins

MCP defines how an LLM interacts with external tools via JSON-RPC. In a
construction context, MCP might be used by a Site Agent to:
- Query a map service for zone boundaries
- Retrieve weather data for scheduling decisions
- Access a fleet management database

CAP then takes over for the **operational coordination**:
- Dispatching `WorkOrder` messages to Machine Agents
- Managing `ReservationState` to prevent load-point collisions
- Negotiating `HandoverEvent` when a machine needs human intervention
- Tracking `ProgressEvent` to monitor task completion

```
┌─────────────────────────────────────────────┐
│  Site Agent (Strategic Layer [A])            │
│  ┌─────────────────────────────────┐        │
│  │ LLM (Claude / Gemini / etc.)    │        │
│  │   ↕ MCP (tool calls)            │        │
│  │   - Map service                 │        │
│  │   - Weather API                 │        │
│  │   - Fleet database              │        │
│  └─────────────────────────────────┘        │
│            ↕ CAP protocol                   │
├─────────────────────────────────────────────┤
│  Machine Agent 1    Machine Agent 2    ...  │
│  (Tactical [B])     (Tactical [B])          │
├─────────────────────────────────────────────┤
│  Safety Supervisor (Execution [C])          │
│  (independent, deterministic, 100Hz+)       │
└─────────────────────────────────────────────┘
```

## What CAP Provides That MCP Does Not

### 1. Safety-Critical State Machines

CAP defines five normative state machines with exhaustive transition tables
(Ch06). Invalid transitions return `CapError(2001)`. The state machines are
**formally verified** in TLA+ (see `formal/tla/`):

- **TaskState**: 9 states, terminal states are absorbing, at most one active task
- **MachineMode**: MANUAL → TELEOP → SUPERVISED_AUTONOMY → AUTONOMY, with SAFE_STOP
  reachable from all states
- **ReservationState**: No double-grant proven for N machines, M resources
- **HandoverEvent**: Timeout always leads to SAFE_STOP
- **DialogueFlow**: Approval required for TASK/CROSS_TASK scope decisions

MCP has no notion of state machines or formal safety properties.

### 2. Multi-Machine Coordination

CAP's reservation protocol prevents deadlocks when multiple machines compete for
shared resources (load points, route segments, zones). The `CAPCoordination.tla`
model verifies deadlock-freedom and starvation-freedom for multi-machine scenarios.

MCP is a point-to-point protocol between one LLM and one tool server.

### 3. Safety Supervisor Independence

CAP's safety channel (ADR-003) operates independently of the protocol runtime.
The Safety Supervisor can trigger `SAFE_STOP` regardless of CAP state, network
conditions, or LLM behavior. This exceeds ISO 17757 / ISO 19014 expectations.

MCP has no concept of a safety supervisor or emergency stop.

### 4. Auditability and Provenance

Every CAP message carries:
- `MessageHeader` with `plan_hash`, `correlation_id`, `sent_at`
- `DialogueProvenance` with `model_id`, `confidence`, `reasoning_summary`
- `AuditEvent` for full traceability

This enables post-incident analysis: which LLM made which decision, when, and why.

### 5. Transport Neutrality

CAP's semantics are defined by protobuf, not transport. The same protocol works
over gRPC (low-latency), MQTT (IoT/constrained), and WebSocket (browser).
MCP is tied to stdio and Streamable HTTP.

### 6. Language-Grounded Object Representation (Entity Descriptor)

CAP integrates Entity Descriptors (Ochiai et al., 2304.04498) to give
every entity (zone, machine, material) a language-grounded description. This
enables LLM-based reasoning about the construction site state.

## When to Use MCP with CAP

A practical deployment may use **both** protocols:

1. **MCP** connects the Site Agent's LLM to external data sources (weather, maps,
   schedules, regulatory databases)
2. **CAP** connects the Site Agent to Machine Agents for operational coordination
3. The Site Agent translates MCP tool results into CAP `WorkOrder` dispatches

This is analogous to how a construction site manager (MCP = their phone/laptop for
information) coordinates crane operators and truck drivers (CAP = their radio
protocol for operational commands).

## Comparison with Other Standards

| Aspect | VDA 5050 | MCP | CAP |
|--------|----------|-----|-----|
| Domain | AGV navigation | LLM tools | Construction machinery |
| Multi-machine | No (single AGV) | No (single LLM) | Yes (fleet coordination) |
| Safety model | Optional | None | Mandatory (ADR-003) |
| State machines | Yes (2) | No | Yes (5, TLA+-verified) |
| LLM integration | No | Core purpose | Yes (3-layer: Site [A] + Machine [B] + Safety [C]) |
| Transport | Single (MQTT assumed) | stdio, HTTP | gRPC, MQTT, WebSocket |
| Formal verification | No | No | Yes (TLA+) |
| Conformance levels | 1 | None | 3 (Core, Coordination, Intelligence) |
| Spec maturity | Production (1000s of AGVs) | Growing adoption | Research (simulation-verified) |

## Summary

**CAP and MCP solve different problems.** MCP is how LLMs talk to tools.
CAP is how LLM-powered agents coordinate safety-critical machinery fleets.
Using MCP where CAP is needed would be like using HTTP for real-time flight control —
technically possible, but missing the safety guarantees, state management, and
multi-agent coordination that the domain demands.
