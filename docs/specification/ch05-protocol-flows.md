<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 5: Protocol Flows

> **Normative.** This chapter defines the required message sequences for all CAP
> protocol flows. Implementations MUST follow these sequences.

---

## 5.1 Connection Flow

Every CAP session begins with a connection handshake.

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: [Transport connect] (TLS/mTLS handshake)
    M->>S: CapFrame { CapabilityManifest }
    Note over S: Register machine, store manifest
    Note over S: Extract entity descriptor if present

    loop Every heartbeat_interval (default 5s)
        M->>S: CapFrame { Heartbeat }
        Note over S: Update last_heartbeat timestamp
    end
```

**Rules:**
1. The first CapFrame from Machine Agent MUST be a CapabilityManifest.
2. Any other message before CapabilityManifest → `CapError(2006)`.
3. Heartbeat MUST begin within one `heartbeat_interval` after connection.

---

## 5.2 WorkOrder Lifecycle

The standard task assignment and execution flow.

```mermaid
sequenceDiagram
    participant S as Site Agent
    participant M as Machine Agent

    S->>M: CapFrame { WorkOrder(task_id, skill, zones, params) }
    Note over M: Validate skill, capacity, mode

    alt Machine accepts
        M->>S: CapFrame { WorkOrderAck(ACCEPTED) }
        Note over M: Begin execution
        loop Progress reporting
            M->>S: CapFrame { ProgressEvent(RUNNING, completion_ratio) }
        end
        M->>S: CapFrame { ProgressEvent(SUCCEEDED, 1.0) }
    else Machine rejects
        M->>S: CapFrame { WorkOrderAck(REJECTED, reason) }
    else Machine defers
        M->>S: CapFrame { WorkOrderAck(DEFERRED, retry_after_sec) }
    else Response timeout
        Note over S: response_window.latest exceeded
        Note over S: Mark task EXPIRED, may reassign
    end
```

---

## 5.3 Cancellation Flow

The Site Agent can cancel a task at any non-terminal state.

```mermaid
sequenceDiagram
    participant S as Site Agent
    participant M as Machine Agent

    S->>M: CapFrame { WorkOrder(task_id=T1) }
    M->>S: CapFrame { WorkOrderAck(ACCEPTED) }
    M->>S: CapFrame { ProgressEvent(RUNNING, 0.3) }

    S->>M: CapFrame { CancelWorkOrder(task_id=T1) }
    Note over M: Stop execution safely
    M->>S: CapFrame { ProgressEvent(CANCELLED) }
```

**Rules:**
1. Machine MUST stop execution safely (not abruptly) upon receiving CancelWorkOrder.
2. Machine MUST send a final ProgressEvent with state=CANCELLED.
3. CancelWorkOrder for a task in terminal state → `CapError(2001)`.

---

## 5.4 Handover Flow

Transition from autonomous to human-operated control.

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent
    participant O as Operator

    Note over M: Obstacle detected during autonomous excavation
    M->>S: CapFrame { HandoverEvent(requested_mode=TELEOP, reason="obstacle", response_window=5min) }
    Note over S: Notify operator

    S->>O: Alert: Handover requested for excavator-01

    alt Operator acknowledges within response_window
        O->>S: Acknowledge handover
        S->>M: CapFrame { ModeCommand(TELEOP) }
        Note over M: Transition to TELEOP
        M->>S: CapFrame { Heartbeat(current_mode=TELEOP) }
        Note over S: Handover complete

        Note over O: Operator resolves obstacle
        O->>S: Return to autonomous
        S->>M: CapFrame { ModeCommand(SUPERVISED_AUTONOMY) }
        M->>S: CapFrame { Heartbeat(current_mode=SUPERVISED_AUTONOMY) }

    else Response window expires
        Note over M: Enter SAFE_STOP autonomously
        M->>S: CapFrame { Heartbeat(current_mode=SAFE_STOP) }
        M->>S: CapFrame { SafetyEvent(event_type="handover_timeout") }
    end
```

---

## 5.5 Reservation Flow

Resource reservation for multi-machine coordination.

```mermaid
sequenceDiagram
    participant M1 as Excavator-01
    participant S as Site Agent
    participant M2 as Dump-01

    M1->>S: CapFrame { ReservationRequest(resource=load-point-A, duration=120s) }
    Note over S: Check availability
    S->>M1: CapFrame { ReservationStatus(GRANTED, window=120s) }

    Note over M1: Working at load-point-A

    M2->>S: CapFrame { ReservationRequest(resource=load-point-A, duration=60s) }
    Note over S: Conflict — load-point-A held by Excavator-01
    S->>M2: CapFrame { ReservationStatus(DENIED, reason="held by excavator-01") }
    Note over M2: Wait and retry

    Note over M1: Work complete
    M1->>S: CapFrame { ReservationRelease(resource=load-point-A) }
    Note over S: Resource released

    M2->>S: CapFrame { ReservationRequest(resource=load-point-A, duration=60s) }
    S->>M2: CapFrame { ReservationStatus(GRANTED, window=60s) }
```

---

## 5.6 Agent Dialogue Flow

Structured communication between Machine Agent and Site Agent.

### 5.6.1 Situation Report

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: CapFrame { AgentDialogue { DialogueMessage(intent=SITUATION_REPORT, SituationReport) } }
    Note over S: Process situation, update world model
    S->>M: CapFrame { AgentDialogue { DialogueMessage(intent=ACKNOWLEDGEMENT) } }
```

### 5.6.2 Local Decision with Approval

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: CapFrame { AgentDialogue { DialogueMessage(intent=LOCAL_DECISION, scope=TASK, approved=false) } }
    Note over S: Evaluate decision
    alt Approve
        S->>M: CapFrame { AgentDialogue { DialogueMessage(intent=ACKNOWLEDGEMENT, approved=true) } }
        Note over M: Execute decision
    else Reject
        S->>M: CapFrame { AgentDialogue { DialogueMessage(intent=ACKNOWLEDGEMENT, approved=false) } }
        Note over M: Revert to original plan
    end
```

### 5.6.3 Plan Proposal

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: CapFrame { AgentDialogue { DialogueMessage(intent=PLAN_PROPOSAL, PlanProposal) } }
    Note over S: Evaluate proposal against constraints
    alt Accept proposal
        S->>M: CapFrame { AgentDialogue { DialogueMessage(intent=ACKNOWLEDGEMENT, approved=true) } }
        S->>M: CapFrame { WorkOrder (updated parameters) }
    else Reject proposal
        S->>M: CapFrame { AgentDialogue { DialogueMessage(intent=INSTRUCTION, text="Continue original plan") } }
    end
```

---

## 5.7 Entity-Descriptor Synchronization Flow

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    Note over M: Machine state changes significantly
    M->>S: CapFrame { EntityStateUpdate(descriptor=updated_descriptor, reason="task_progress") }
    Note over S: Update entity in world model

    Note over S: Entity interaction occurs (e.g., excavator interacts with soil)
    S->>M: CapFrame { EntityInteraction(initiator=excavator-01, target=soil-B3, type="excavate") }
```

---

## 5.8 Reconnection Flow

Recovery after a network partition or machine restart.

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: CapFrame { ProgressEvent(RUNNING, 0.6) }
    Note over M,S: ── Network partition ──

    Note over S: Heartbeat timeout (15s) → mark DISCONNECTED
    Note over S: Start grace period (30s)

    Note over M: Detect disconnect → enter SAFE_STOP
    Note over M: Exponential backoff reconnection attempts

    M->>S: [Transport reconnect]
    M->>S: CapFrame { CapabilityManifest }
    M->>S: CapFrame { Heartbeat(active_task_id=T1, current_mode=SAFE_STOP) }

    alt Within grace period
        Note over S: Task T1 still in RUNNING → resume
        S->>M: CapFrame { ModeCommand(SUPERVISED_AUTONOMY) }
        M->>S: CapFrame { ProgressEvent(RUNNING, 0.6) }
        Note over M,S: Task resumes
    else Grace period expired
        Note over S: Task T1 → FAILED(machine_disconnected)
        S->>M: CapFrame { CancelWorkOrder(task_id=T1) }
        Note over S: Re-plan if needed
    end
```

---

## 5.9 Excavate-and-Haul Cycle (End-to-End)

Complete cycle involving two machines cooperating.

```mermaid
sequenceDiagram
    participant S as Site Agent
    participant E as Excavator-01
    participant D as Dump-01

    Note over S: GoalSpec → TaskGraph compiled

    S->>E: WorkOrder(T1: excavate_batch, zone=B3, 6m³)
    E->>S: WorkOrderAck(ACCEPTED)

    S->>D: WorkOrder(T2: haul_route, depends_on=[T1])
    Note over D: T2 in PENDING until T1 progresses

    E->>S: ProgressEvent(RUNNING, 0.5)
    E->>S: AgentDialogue(SituationReport: "hard soil layer")
    S->>E: AgentDialogue(INSTRUCTION: "reduce depth, continue")

    E->>S: ProgressEvent(RUNNING, 0.9)

    Note over S: Reserve load-point for handoff
    S->>E: ReservationRequest(load-point-A)
    Note over S: Grant to excavator

    E->>S: ProgressEvent(SUCCEEDED, 1.0)

    Note over S: Signal dump truck to approach
    D->>S: WorkOrderAck(ACCEPTED)
    D->>S: ProgressEvent(RUNNING, 0.2) [moving to load point]

    Note over S: Excavator loads dump truck
    D->>S: ProgressEvent(RUNNING, 0.5) [loaded, hauling]
    D->>S: ProgressEvent(RUNNING, 0.8) [at dump zone]
    D->>S: ProgressEvent(SUCCEEDED, 1.0)

    Note over S: Release reservations, cycle complete
```

---

## 5.10 Error Flow

See Chapter 8 for detailed error handling. Summary flow:

```mermaid
sequenceDiagram
    participant M as Machine Agent
    participant S as Site Agent

    M->>S: CapFrame { invalid message }
    S->>M: CapFrame { CapError(code, domain, message, related_message_id) }
    Note over M,S: Stream remains open (unless CRITICAL)
```
