<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 2: Terms and Definitions

For the purposes of this specification, the following terms and definitions apply.
Terms defined here are used throughout the specification in *italics* on first occurrence
in each chapter.

---

**Abstract Language Object (ALO)**
: A structured, language-grounded representation of a physical or logical entity
  (machine, zone, material) based on Ochiai (2304.04498). Each ALO has an identifier,
  canonical name, typed properties, sub-objects, and a manager describing available
  skills and interaction rules.

**Agent Dialogue**
: A structured communication exchange between a *Machine Agent* and a *Site Agent*,
  consisting of one or more *DialogueMessage* instances within a single *AgentDialogue*
  envelope.

**Audit Event**
: A recorded action or decision within the CAP system, including the actor, subject,
  action, result, and reason. Used for compliance, traceability, and replay.

**CapFrame**
: The universal message envelope for all CAP communications. Every message on the wire
  is wrapped in a CapFrame, which contains a *MessageHeader* and exactly one body message.

**Capability Manifest**
: A declaration sent by a *Machine Agent* upon connection, describing the machine's
  identity, type, skills, and current state. It is the first message in any CAP stream.

**Conformance Level**
: A tier of CAP specification compliance. Level 1 (Core) covers basic connectivity and
  task lifecycle; Level 2 (Coordination) adds reservations and handovers; Level 3
  (Intelligence) adds ALO and agent dialogue.

**Dialogue Provenance**
: Metadata attached to each *DialogueMessage* recording the generating agent, model
  identifier, confidence score, and reasoning summary. Used for auditability and
  transparency.

**Fault Event**
: A report of a machine or task fault, including severity, fault code, and whether
  handover or safe stop is required.

**GoalSpec**
: A structured description of a construction objective (e.g., "excavate 50m³ from zone
  B3 and haul to dump zone D1"), defined in JSON with Pydantic validation. The *Site
  Agent* compiles a GoalSpec into a *TaskGraph*.

**Handover Event**
: A request to transition control between autonomous and human-operated modes.
  Handovers follow a negotiated flow (REQUESTED → ACKNOWLEDGED → IN_PROGRESS →
  COMPLETED or TIMED_OUT).

**Heartbeat**
: A periodic message sent by a *Machine Agent* to indicate aliveness and report current
  state (mode, health, position, active task, fuel, ALO state summary).

**Layer [A] (Strategic)**
: The *Site Agent* layer responsible for task planning, decomposition, and multi-machine
  coordination. May use large LLMs for natural language understanding and planning.

**Layer [B] (Tactical)**
: The *Machine Agent* layer responsible for situation awareness, local decisions, and
  advisory reports. May use SLMs/LLMs in an advisory role only — never directly
  controlling actuators.

**Layer [C] (Execution)**
: The *Safety Supervisor* and low-level control layer. Operates at 100Hz+ with
  deterministic logic. Independent of CAP. No LLM involvement.

**Local Decision**
: A decision made by a *Machine Agent* categorized by scope: MICRO (autonomous, no
  approval needed), TASK (requires *Site Agent* approval), or CROSS_TASK (requires
  approval and may affect other machines).

**Machine Agent**
: A software component running on or near a construction machine that communicates with
  the *Site Agent* via CAP. Responsible for executing *WorkOrders*, reporting progress,
  and providing situation reports.

**Machine Mode**
: The operating autonomy level of a machine: MANUAL, TELEOP, SUPERVISED_AUTONOMY,
  AUTONOMY, SAFE_STOP, or MAINTENANCE. Transitions are governed by the MachineMode
  state machine (Chapter 6).

**Message Header**
: Metadata attached to every *CapFrame*: message_id (UUID), sender_id, receiver_id,
  correlation_id, work_package_id, plan_hash, and sent_at timestamp.

**Plan Hash**
: A SHA-256 hash of a *GoalSpec* that uniquely identifies a construction plan.
  Propagated to all *WorkOrders* and events derived from the plan, enabling end-to-end
  traceability.

**Progress Event**
: A report from a *Machine Agent* on the current state of an assigned task, including
  *TaskState*, completion ratio, summary, and metrics.

**Reservation**
: An exclusive claim on a shared resource (zone, load point, route segment) granted
  by the *Site Agent* to prevent conflicts between machines. Governed by the
  ReservationState state machine (Chapter 6).

**Safe Stop**
: An emergency state where all machine actuators are inhibited. Can only be triggered
  by the *Safety Supervisor*. Exit requires physical on-machine reset.

**Safety Event**
: A report of a safety-critical state change (geofence violation, human detection,
  etc.), including severity and whether motion is inhibited.

**Safety Supervisor**
: An independent system (Layer [C]) responsible for geofence enforcement, human
  detection, E-stop management, and motion inhibition. Operates independently of CAP.

**Site Agent**
: A software component responsible for coordinating multiple *Machine Agents* on a
  construction site. Receives *GoalSpecs*, compiles *TaskGraphs*, dispatches
  *WorkOrders*, manages reservations, and processes events.

**Skill**
: A named capability declared in a *Capability Manifest* (e.g., `excavate_batch`,
  `haul_route`, `load_truck`, `safe_wait`). *WorkOrders* reference skills by name.

**Task Graph**
: A directed acyclic graph (DAG) of dependent tasks compiled from a *GoalSpec*.
  Each node is a *WorkOrder* with dependencies on other tasks.

**Task State**
: The lifecycle state of a *WorkOrder*: PENDING, ACCEPTED, RUNNING, BLOCKED,
  SUCCEEDED, FAILED, CANCELLED, REJECTED, or EXPIRED. Governed by the TaskState
  state machine (Chapter 6).

**Transport Profile**
: A specification of how *CapFrame* messages are transmitted over a specific transport
  protocol (gRPC, MQTT, WebSocket). See Chapter 4.

**Work Order**
: A task assignment from the *Site Agent* to a *Machine Agent*, specifying a skill,
  target zones, parameters, constraints, and execution window.

**Work Package**
: A collection of related *WorkOrders* derived from a single *GoalSpec*, identified
  by a work_package_id and plan_hash.
