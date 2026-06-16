<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 10: Conformance

> **Normative.** This chapter defines the conformance levels and criteria for CAP
> implementations.

---

## 10.1 Conformance Levels

CAP defines three conformance levels. Each level includes all requirements of
lower levels.

| Level | Name | Description |
|-------|------|-------------|
| **Level 1** | **Core** | Basic connectivity, task lifecycle, and error handling |
| **Level 2** | **Coordination** | Multi-machine coordination with reservations and handovers |
| **Level 3** | **Intelligence** | Entity-descriptor integration and agent dialogue |

---

## 10.2 Level 1: Core

An implementation claiming Level 1 conformance MUST:

### 10.2.1 Connection

- [ ] Send `CapabilityManifest` as the first message in any CAP stream
- [ ] Reject any message received before `CapabilityManifest` with `CapError(2006)`
- [ ] Send `Heartbeat` at the configured interval (default 5 seconds)
- [ ] Detect heartbeat timeout (default 15 seconds) and mark machine as disconnected

### 10.2.2 WorkOrder Lifecycle

- [ ] Implement the full `TaskState` state machine (Chapter 6, §6.1)
- [ ] Respond to `WorkOrder` with `WorkOrderAck` (ACCEPTED, REJECTED, or DEFERRED)
- [ ] Send `ProgressEvent` with valid state transitions during task execution
- [ ] Report `completion_ratio = 1.0` when state is `SUCCEEDED`
- [ ] Handle `CancelWorkOrder` at any non-terminal state → transition to `CANCELLED`

### 10.2.3 Error Handling

- [ ] Respond to invalid state transitions with `CapError(2001)`
- [ ] Respond to unrecognized message types with `CapError(2002)`
- [ ] Respond to invalid messages with `CapError(2004)`
- [ ] NOT close the stream on non-CRITICAL errors
- [ ] Include `related_message_id` in `CapError` responses

### 10.2.4 Reconnection

- [ ] Machine Agent: reconnect with exponential backoff after stream failure
- [ ] Machine Agent: send fresh `CapabilityManifest` on reconnect
- [ ] Site Agent: implement grace period for disconnected machines

### 10.2.5 Message Format

- [ ] Include valid `MessageHeader` (message_id, sender_id, sent_at) in all CapFrames
- [ ] Use UUID v4 for `message_id`
- [ ] Preserve `correlation_id` in responses

---

## 10.3 Level 2: Coordination

In addition to Level 1 requirements, Level 2 conformance MUST:

### 10.3.1 Reservations

- [ ] Implement `ReservationState` state machine (Chapter 6, §6.3)
- [ ] Process `ReservationRequest` and respond with `ReservationStatus`
- [ ] Detect and deny conflicting reservations
- [ ] Automatically expire reservations when `granted_window.latest` elapses
- [ ] Process `ReservationRelease`

### 10.3.2 Mode Management

- [ ] Implement `MachineMode` state machine (Chapter 6, §6.2)
- [ ] Process `ModeCommand` and enforce valid transitions
- [ ] Reject invalid mode transitions with `CapError(2001)`
- [ ] Report `current_mode` accurately in `Heartbeat`

### 10.3.3 Handover

- [ ] Implement `HandoverEvent` flow (Chapter 6, §6.4)
- [ ] Machine Agent: enter `SAFE_STOP` if handover response window expires
- [ ] Site Agent: process HandoverEvent and issue ModeCommand

### 10.3.4 Safety Events

- [ ] Process and route `SafetyEvent` messages
- [ ] Process and route `FaultEvent` messages

### 10.3.5 Transport Security

- [ ] Support TLS 1.3 for all connections
- [ ] Support at least one authentication mechanism (mTLS or JWT)

---

## 10.4 Level 3: Intelligence

In addition to Level 2 requirements, Level 3 conformance MUST:

### 10.4.1 Entity-Descriptor Integration

- [ ] Include `EntityDescriptor` in `CapabilityManifest`
- [ ] Send `EntityStateUpdate` when machine state changes significantly
- [ ] Process `EntityInteraction` messages
- [ ] Include `entity_state_summary` in `Heartbeat`

### 10.4.2 Agent Dialogue

- [ ] Implement `DialogueFlow` (Chapter 6, §6.5)
- [ ] Process all `DialogueIntent` types
- [ ] Include `DialogueProvenance` in all dialogue messages
- [ ] Enforce `LocalDecisionScope` approval rules:
  - `MICRO`: machine may execute without approval
  - `TASK` / `CROSS_TASK`: machine MUST NOT execute until approved

### 10.4.3 Security (Full)

- [ ] Support mTLS for machine-to-site authentication
- [ ] Implement RBAC per Chapter 9
- [ ] Record all authorization decisions in audit trail

---

## 10.5 Conformance Test Suites

The `cap-conformance` repository provides automated test suites:

| Suite | Level | Tests | Description |
|-------|-------|-------|-------------|
| `test_handshake` | 1 | 2 | Manifest registration, HAL profile |
| `test_heartbeat` | 1 | 2 | Heartbeat aliveness, field validation |
| `test_work_order_lifecycle` | 1 | 3 | Accept, reject, progress to succeeded |
| `test_error_handling` | 1 | 4+ | Invalid transitions, unknown messages, invalid messages |
| `test_concurrent_work_orders` | 1 | 1+ | Busy machine rejection |
| `test_reconnection` | 1 | 1+ | Disconnect and reconnect |
| `test_timeout_cascade` | 2 | 1+ | Heartbeat timeout → SAFE_STOP |
| `test_entity_descriptor_lifecycle` | 3 | 3 | Entity descriptor in manifest, state updates, heartbeat summary |
| `test_dialogue` | 3 | 4 | Round-trip, provenance, intent, approval |

---

## 10.6 Conformance Declaration

An implementation claiming CAP conformance MUST:

1. State the conformance level (1, 2, or 3).
2. State the supported transport profile(s) (gRPC, MQTT, WebSocket).
3. Pass all test suites for the claimed level using the `cap-conformance` test runner.
4. Publish test results (pass/fail per suite).

Example conformance declaration:

```
CAP Conformance: Level 2
Transports: gRPC, MQTT
Test Results: cap-conformance v0.1.0
  Level 1: 12/12 passed
  Level 2: 8/8 passed
```

---

## 10.7 Feature Classification

| Feature | Required Level | Status |
|---------|---------------|--------|
| CapabilityManifest | 1 | MUST |
| Heartbeat | 1 | MUST |
| WorkOrder lifecycle | 1 | MUST |
| CapError | 1 | MUST |
| Reconnection | 1 | MUST |
| ReservationRequest/Status | 2 | MUST |
| ModeCommand | 2 | MUST |
| HandoverEvent | 2 | MUST |
| SafetyEvent/FaultEvent | 2 | MUST |
| TLS 1.3 | 2 | MUST |
| EntityDescriptor | 3 | MUST |
| EntityStateUpdate | 3 | MUST |
| AgentDialogue | 3 | MUST |
| DialogueProvenance | 3 | MUST |
| mTLS + RBAC | 3 | MUST |
| EntityInteraction | 3 | SHOULD |
| AuditEvent | 2 | SHOULD |
| Version negotiation | 1 | SHOULD |
| MQTT transport | — | OPTIONAL |
| WebSocket transport | — | OPTIONAL |
