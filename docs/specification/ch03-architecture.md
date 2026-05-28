<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 3: Architecture Overview

> **Informative.** This chapter describes the overall system architecture to provide
> context for the normative chapters that follow.

---

## 3.1 Three-Layer Architecture

CAP operates within a three-layer architecture that separates strategic intelligence,
tactical awareness, and safety-critical execution:

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer [A]: Site Agent (Strategic)                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ GoalSpec │→│ Task     │→│ Work     │→│ Reservation   │  │
│  │ Planner  │  │ Compiler │  │ Dispatcher│  │ Manager       │  │
│  │ (LLM)    │  │ (determ.)│  │          │  │               │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────────────┘  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│  │ Dialogue │  │ ALO World│  │ Audit    │                     │
│  │ Handler  │  │ Model    │  │ Service  │                     │
│  └──────────┘  └──────────┘  └──────────┘                     │
├─────────────────── CAP Protocol ──────────────────────────────┤
│  Layer [B]: Machine Agent (Tactical)          × N machines     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│  │ Skill    │  │ Situation│  │ ALO      │                     │
│  │ Executor │  │ Assessor │  │ Descriptor│                     │
│  │          │  │ (SLM/LLM)│  │ Generator│                     │
│  └──────────┘  └──────────┘  └──────────┘                     │
├───────────────────────────────────────────────────────────────┤
│  Layer [C]: Safety Supervisor (Execution)     independent      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│  │ Geofence │  │ Human    │  │ E-Stop   │                     │
│  │ Monitor  │  │ Detector │  │ Manager  │                     │
│  └──────────┘  └──────────┘  └──────────┘                     │
│  ← Deterministic, 100Hz+, no LLM →                            │
└─────────────────────────────────────────────────────────────────┘
```

### 3.1.1 Layer [A]: Site Agent

The Site Agent is the central coordinator for a construction site. It:

- Receives construction objectives as GoalSpecs (natural language or structured JSON)
- Uses an LLM planner to convert GoalSpecs into structured plans
- Compiles plans into TaskGraphs (deterministic compilation, no LLM)
- Dispatches WorkOrders to Machine Agents via CAP
- Manages reservations to prevent resource conflicts
- Processes events, dialogues, and fault reports from Machine Agents
- Maintains an ALO-based world model of all site entities
- Records all actions in the audit trail

### 3.1.2 Layer [B]: Machine Agent

Each Machine Agent runs on or near a physical construction machine. It:

- Connects to the Site Agent via CAP (gRPC, MQTT, or WebSocket)
- Declares its capabilities via CapabilityManifest
- Receives and executes WorkOrders
- Reports progress, faults, and safety events
- Provides situation reports and plan proposals via Agent Dialogue
- Maintains and synchronizes its ALO descriptor
- May use an SLM/LLM for situation assessment (advisory only)

**Key constraint**: Layer [B] LLMs are **advisory only**. They generate situation reports
and recommendations but NEVER directly control actuators.

### 3.1.3 Layer [C]: Safety Supervisor

The Safety Supervisor is independent of CAP (see ADR-003):

- Operates on a separate communication channel
- Runs deterministic logic at 100Hz or higher
- Can unilaterally trigger SAFE_STOP regardless of CAP state
- Handles geofence enforcement, human detection, and E-stop management
- CAP's SafetyEvent is **informational** — it reports what happened, not controls it

---

## 3.2 Component Diagram

```
                    ┌───────────────┐
                    │  Operator     │
                    │  Console      │
                    │  (WebSocket)  │
                    └───────┬───────┘
                            │
┌───────────────────────────┼───────────────────────────────────┐
│  Field Platform           │                                    │
│  ┌────────────┐  ┌────────┴───────┐  ┌──────────────────┐    │
│  │ GoalSpec   │  │  Dashboard     │  │  Audit Service   │    │
│  │ Planner    │  │  (FastAPI+WS)  │  │  (plan_hash      │    │
│  │ (LLM)      │  └────────────────┘  │   traceability)  │    │
│  └────┬───────┘                      └──────────────────┘    │
│       │                                                       │
│  ┌────┴───────┐  ┌────────────────┐  ┌──────────────────┐    │
│  │ Task       │  │  Reservation   │  │  ALO World       │    │
│  │ Compiler   │  │  Service       │  │  Model           │    │
│  └────┬───────┘  └────────────────┘  └──────────────────┘    │
│       │                                                       │
│  ┌────┴──────────────────────────────────────────────────┐   │
│  │  Site Agent (CapRuntimeService)                        │   │
│  │  gRPC :50051  |  MQTT broker :1883  |  WS :8200        │   │
│  └──────────┬───────────┬──────────────┬─────────────────┘   │
└─────────────┼───────────┼──────────────┼─────────────────────┘
              │           │              │
        ┌─────┘           │              └──────┐
        │                 │                     │
┌───────┴───────┐  ┌──────┴──────┐  ┌──────────┴─────┐
│ Excavator-01  │  │ Dump-01     │  │ Excavator-02   │
│ Machine Agent │  │ Machine Agent│  │ Machine Agent  │
│ (gRPC/MQTT)   │  │ (gRPC/MQTT) │  │ (gRPC/MQTT)    │
├───────────────┤  ├─────────────┤  ├────────────────┤
│ Safety        │  │ Safety      │  │ Safety         │
│ Supervisor    │  │ Supervisor  │  │ Supervisor     │
│ (independent) │  │ (independent)│ │ (independent)  │
└───────────────┘  └─────────────┘  └────────────────┘
```

---

## 3.3 ALO Integration Model

Abstract Language Objects (ALO) provide a unified representation model across CAP:

```
┌─── ALO World Model (Site Agent) ──────────────────────────────┐
│                                                                │
│  Zone ALOs           Machine ALOs           Material ALOs      │
│  ┌──────────┐       ┌──────────────┐       ┌──────────────┐  │
│  │ B3区画    │       │ バックホウ1号機│       │ 土砂-B3      │  │
│  │ type:zone │       │ type:machine │       │ type:material│  │
│  │ volume:   │       │ skills: [..] │       │ volume: 50m³ │  │
│  │  50m³     │       │ mode: AUTO   │       │ density: ..  │  │
│  └──────────┘       └──────────────┘       └──────────────┘  │
│                                                                │
│  Relations: machine --operates_in--> zone                     │
│             machine --carries--> material                     │
│             zone --adjacent_to--> zone                        │
└───────────────────────────────────────────────────────────────┘
```

- **CapabilityManifest** carries the machine's `ALODescriptor` on connection.
- **Heartbeat** carries `alo_state_summary` (natural language state description).
- **ALOStateUpdate** synchronizes machine ALO state with the Site Agent's world model.
- **ALOInteraction** records interactions between ALO entities.

---

## 3.4 Message Flow Overview

The following shows the high-level message flow for a typical excavation cycle:

```
Site Agent                          Machine Agent (Excavator)
    │                                        │
    │←── CapabilityManifest ────────────────│  (1) Connect
    │                                        │
    │←── Heartbeat ─────────────────────────│  (2) Periodic health
    │                                        │
    │──── WorkOrder(excavate_batch) ────────→│  (3) Task assignment
    │                                        │
    │←── WorkOrderAck(ACCEPTED) ────────────│  (4) Acceptance
    │                                        │
    │←── ProgressEvent(RUNNING, 30%) ───────│  (5) Progress
    │                                        │
    │←── AgentDialogue(SituationReport) ────│  (6) Hard soil detected
    │──── AgentDialogue(INSTRUCTION) ───────→│  (7) Continue, reduce depth
    │                                        │
    │←── ProgressEvent(RUNNING, 80%) ───────│  (8) Progress
    │                                        │
    │←── HandoverEvent(TELEOP) ─────────────│  (9) Obstacle detected
    │──── ModeCommand(TELEOP) ──────────────→│  (10) Mode change
    │                                        │
    │←── ProgressEvent(SUCCEEDED) ──────────│  (11) Complete
    │                                        │
```

Detailed sequence diagrams for all normal and abnormal flows are provided in Chapter 5.

---

## 3.5 Deployment Topologies

### 3.5.1 Single-Site (Reference)

One Site Agent coordinates all machines on a single construction site. This is the
topology used by the reference implementation and conformance tests.

### 3.5.2 Multi-Site (Future)

Multiple Site Agents, each managing a site, with a federation layer for cross-site
coordination. Not defined in CAP v0.x.

### 3.5.3 Simulator Integration

For development and testing, the reference implementation includes a lightweight 2D
simulator that replaces physical machines:

```
Site Agent ←→ (CAP/gRPC) ←→ Sim Machine Agent ←→ (HTTP) ←→ Simulator Engine
```

The Simulator Engine provides a tick-based physics model (terrain, excavation, hauling)
and exposes state via HTTP API. Sim Machine Agents translate simulator events into
CAP ProgressEvents and HandoverEvents.
