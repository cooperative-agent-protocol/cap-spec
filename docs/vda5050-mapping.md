<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP ↔ VDA 5050 Crosswalk

A field-level mapping between **VDA 5050 v2.0.0** (the open standard for
communication between mobile-robot fleets and a central fleet controller, widely
adopted in intralogistics) and **CAP**. The purpose is to make the relationship
precise: *where the two standards correspond*, and *what CAP adds* for
task-level coordination of heterogeneous construction machines.

VDA 5050 field/enum names below are taken verbatim from the v2.0.0
specification (`VDA5050/VDA5050`); CAP names refer to the message reference in
`docs/specification/ch07-message-reference.md`.

## Why not simply extend VDA 5050?

VDA 5050 and CAP are both typed message protocols over MQTT/transport, but they
sit at different abstraction levels and standardise different things:

1. **Route-level vs task-level.** A VDA 5050 `order` is a **pre-computed route**
   — an ordered list of `nodes[]` and `edges[]` (with `position {x, y, theta,
   mapId}`) that the *fleet controller* plans and the vehicle follows. A CAP
   `WorkOrder` is a **task** (`skill`, e.g. `excavate_batch`, plus typed
   `SkillInvocation` parameters and zone references); the machine plans its own
   motion. CAP coordinates *what to do*, not *which nodes to traverse*.

2. **Schemas vs verified state machines.** VDA 5050 standardises message schemas
   and reporting; CAP additionally specifies the coordination **state machines**
   (TaskState, ReservationState, MachineMode+Handover) and model-checks
   protocol-safety invariants over them (Properties P1–P7,
   `formal/tla/RESULTS.md`).

3. **No shared-resource / inter-vehicle dependency primitive.** VDA 5050 has no
   representation for one vehicle reserving a shared resource or handing it to
   another; the fleet controller avoids conflicts by **centrally serialising
   routes**. CAP makes resource exclusivity (`Reservation`, P2/P5/P7) and
   machine-to-machine `Handover` (P4) first-class, typed, verified primitives.

## Message-level crosswalk

| VDA 5050 v2.0.0 | Principal fields (verbatim) | CAP equivalent | CAP delta |
|---|---|---|---|
| `order` | `orderId`, `orderUpdateId`, `nodes[]`, `edges[]`, `actions[]` | `WorkOrder` (`task_id`, `skill`, zones, `invocation`) | Task-level skill, not a node/edge route; the machine plans motion. |
| `order.nodes[]` / `edges[]` | `nodeId`/`edgeId`, `sequenceId`, `released`, `position`, `trajectory`, `actions[]` | — (motion-layer; below CAP's task level) | Out of CAP scope by design (CAP is transport- and motion-neutral). |
| `instantActions` | `instantActions[]` of `{actionId, actionType, blockingType, parameters}` | `ModeCommand`, `CancelWorkOrder`, `AgentDialogue` (instruction) | Typed control/coordination messages. |
| `state` | `orderId`, `nodeStates[]`, `edgeStates[]`, `actionStates[]`, `errors[]`, `operatingMode`, `driving`, `paused`, `safetyState`, `mobileRobotPosition`, `load` | `ProgressEvent` + `Heartbeat` | Task-level progress against a verified `TaskState` (P1), not node/edge traversal. |
| `state.actionStates[].state` = `INITIALIZING / RUNNING / PAUSED / FINISHED / FAILED / RETRIABLE` | (per-action) | `TaskState` = `PENDING / ACCEPTED / RUNNING / BLOCKED / SUCCEEDED / FAILED / …` | CAP's lifecycle is model-checked: at-most-one active task, terminal absorption (P1). |
| `state.operatingMode` | (vehicle operating mode field) | `MachineMode` (`MANUAL / TELEOP / SUPERVISED_AUTONOMY / AUTONOMY / SAFE_STOP / MAINTENANCE`) + `ModeCommand` | CAP adds **graduated autonomy** and a typed operator **Handover** flow. |
| `state.errors[]` | `errorType`, `errorLevel` = `WARNING / CRITICAL`, `errorMessage`, `errorReferences[]` | `CapError` (`error_code`, `ErrorDomain`, `severity`) + `FaultEvent` | Comparable structured error model (see ch08). |
| `state.safetyState` | (reported safety status) | `SafetyEvent` (informational) **+ independent Safety Supervisor** | CAP separates a deterministic safety channel (ADR-003), verified non-interfering with the protocol (P6) — VDA 5050 *reports* a safety status but does not specify a verified, protocol-independent supervisor. |
| `connection` | `connectionState` = `ONLINE / OFFLINE / CONNECTION_BROKEN / HIBERNATING`, `timestamp`, `headerId` | `Heartbeat` + reconnection protocol (ch08 §8) | Comparable connection/liveness handling. |
| `factsheet` | `typeSpecification`, `physicalParameters`, protocol features | `CapabilityManifest` + `EntityDescriptor` | CAP advertises typed `capabilities`/skills and a language-grounded entity descriptor. |
| `visualization` | high-frequency position/path | (operator-console concern; CAP WebSocket profile) | Out of the coordination core. |
| — *(no VDA 5050 equivalent)* | — | `ReservationRequest` / `ReservationStatus` (`GRANTED / QUEUED / DENIED / RELEASED / EXPIRED`, `grant_epoch`) | **CAP delta**: typed shared-resource exclusivity, verified (P2 no-double-grant, P5 fencing under lost delivery, P7 deadlock-freedom). |
| — *(no VDA 5050 equivalent)* | — | machine-to-machine `Handover` (`HandoverReceiverOwnership`) | **CAP delta**: direct load-point transfer between machines (P4). |
| — *(no VDA 5050 equivalent)* | — | `AgentDialogue` (`SituationReport`, `PlanProposal`, `LocalDecision`, `DialogueProvenance`) | **CAP delta**: structured inter-agent dialogue with provenance and approval scope. |
| — *(VDA 5050 standardises schemas only)* | — | TLA+ specifications (P1–P7) | **CAP delta**: model-checked protocol-safety invariants. |

## Summary

VDA 5050 is the right standard for **central-fleet AGV logistics**: the
controller plans routes as node/edge graphs and serialises them to avoid
conflicts. CAP targets **decentralised, task-level coordination of heterogeneous
construction machines** that plan their own motion, where shared-resource
exclusivity, machine-to-machine handover, graduated autonomy, structured
dialogue, and an independent verified safety supervisor are first-class
concerns. The four CAP deltas in the table above are exactly the primitives a
VDA-5050-style route-serialisation model does not provide, and they are the ones
CAP formally verifies.
