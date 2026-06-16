<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 1: Scope

## 1.1 Purpose

The **Cooperative Agent Protocol (CAP)** is a domain-agnostic task-level
communication protocol for orchestrating autonomous and semi-autonomous industrial
machinery. CAP defines the message semantics, state machines, error handling, and
transport profiles required to coordinate multiple machine agents under the
supervision of a site agent.

CAP's **core** is intentionally domain-agnostic. Domain-specific concepts (skill
names, zone types, equipment classes) are organized as **Domain Packs**. The v0.x
release ships the **Construction Domain Pack** as the reference domain; future
Domain Packs for Agriculture, Mining, Forestry, and Intralogistics may be
contributed via the RFC process.

CAP enables:

- **Task assignment and lifecycle management** — structured WorkOrders with deterministic
  state tracking from assignment to completion.
- **Multi-machine coordination** — resource reservations, handover events, and agent
  dialogue for collision-free cooperative operations.
- **Human-machine teaming** — graduated autonomy levels (manual → teleop → supervised
  autonomy → full autonomy) with explicit handover protocols.
- **Language-grounded object representation** — entity descriptors provide
  a unified, human-readable description of machines, zones, and materials.
- **Auditability** — every state transition, decision, and plan is traceable via
  plan hashes, dialogue provenance, and audit events.

## 1.2 In Scope

This specification defines:

1. **Message types** — all protobuf message definitions for CAP v0.x
2. **State machines** — normative state transition diagrams and matrices for TaskState,
   MachineMode, ReservationState, HandoverFlow, and DialogueFlow
3. **Error model** — structured error codes, retry semantics, and recovery protocols
4. **Transport profiles** — gRPC (primary), MQTT (IoT), and WebSocket (browser)
5. **Security model** — authentication, authorization, and encryption requirements
6. **Conformance levels** — criteria for implementations to claim CAP conformance
7. **Entity-descriptor integration** — how entity descriptors are used within CAP messages
8. **Agent dialogue** — structured communication between Machine Agents and Site Agents

## 1.3 Out of Scope

This specification does NOT define:

1. **Motion planning or trajectory generation** — CAP operates at the task level,
   not the motion control level.
2. **Safety certification** — CAP is not a safety-certified protocol. The Safety
   Supervisor is an independent system (see `docs/safety-boundary.md`).
3. **Real-time control** — CAP messages are not designed for sub-100ms control loops.
   Layer [C] (Safety Supervisor + actuator control) operates independently.
4. **Specific LLM models or prompts** — the protocol defines interfaces for LLM
   integration but does not mandate specific models or prompt strategies.
5. **Hardware abstraction** — machine-specific HAL implementations are outside CAP.
6. **Construction domain ontology** — while entity descriptors provide a representation model,
   CAP does not define a comprehensive construction ontology.

## 1.4 Relationship to Other Standards

| Standard | Relationship |
|----------|-------------|
| **VDA 5050** | AGV communication standard for logistics. CAP addresses similar concerns (task lifecycle, state machines, transport) but for construction machinery, which requires coordination semantics (reservation, handover) and graduated autonomy absent in VDA 5050. |
| **MCP (Model Context Protocol)** | AI model interaction protocol. CAP's agent dialogue is inspired by MCP's structured tool use but extends it with safety constraints and multi-agent coordination. |
| **ROS 2** | Robot middleware. CAP is transport-neutral and can coexist with ROS 2 at the motion control layer. CAP handles task-level orchestration; ROS 2 handles sensor/actuator I/O. |
| **ISO 15143-3 (AEMP 2.0)** | Telematics data exchange for construction. CAP extends beyond telemetry to active task coordination. |
| **Entity descriptor (Ochiai et al., 2304.04498)** | A language-grounded, typed object representation. CAP adopts it as the representation model for machines, zones, and materials. |

## 1.5 Architecture Overview

CAP operates within a three-layer architecture:

| Layer | Name | Responsibility | LLM Involvement |
|-------|------|----------------|-----------------|
| **[A]** | Site Agent | Strategic planning, task decomposition, multi-machine coordination | Large LLM (Claude, GPT-4, Gemini) |
| **[B]** | Machine Agent | Tactical decisions, situation awareness, advisory reports | SLM/LLM (advisory only, no actuator control) |
| **[C]** | Safety Supervisor | Motion inhibit, geofence, E-stop, 100Hz control | None (deterministic) |

CAP defines the communication between layers [A] and [B]. Layer [C] is independent.

## 1.6 Document Conventions

| Convention | Meaning |
|------------|---------|
| **MUST** | Absolute requirement (RFC 2119) |
| **MUST NOT** | Absolute prohibition |
| **SHOULD** | Recommended but not mandatory |
| **MAY** | Optional |
| `monospace` | Code, message types, field names |
| *italic* | Terms defined in Chapter 2 |
