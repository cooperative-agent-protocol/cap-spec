<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 7: Message Reference

> **Normative.** This chapter provides the complete field-level specification for all
> CAP message types. Source of truth: `proto/cap/v0/*.proto`.

---

## 7.1 Common Types (`common.proto`)

### 7.1.1 Enums

#### MachineType

| Value | Number | Description |
|-------|--------|-------------|
| `MACHINE_TYPE_UNSPECIFIED` | 0 | Default / unknown |
| `MACHINE_TYPE_EXCAVATOR` | 1 | Hydraulic excavator (backhoe) |
| `MACHINE_TYPE_DUMP_TRUCK` | 2 | Articulated or rigid dump truck |
| `MACHINE_TYPE_DOZER` | 3 | Bulldozer |
| `MACHINE_TYPE_GRADER` | 4 | Motor grader |
| `MACHINE_TYPE_LOADER` | 5 | Wheel loader |
| `MACHINE_TYPE_ROLLER` | 6 | Compaction roller |
| `MACHINE_TYPE_CRANE` | 7 | Crane |

#### MachineMode

See Chapter 6, Section 6.2 for state machine semantics.

| Value | Number | Description |
|-------|--------|-------------|
| `MACHINE_MODE_UNSPECIFIED` | 0 | Default / unknown |
| `MACHINE_MODE_MANUAL` | 1 | Full manual control |
| `MACHINE_MODE_TELEOP` | 2 | Remote operation |
| `MACHINE_MODE_SUPERVISED_AUTONOMY` | 3 | Autonomous with human oversight |
| `MACHINE_MODE_AUTONOMY` | 4 | Fully autonomous |
| `MACHINE_MODE_SAFE_STOP` | 5 | Emergency stop (Safety Supervisor only) |
| `MACHINE_MODE_MAINTENANCE` | 6 | Maintenance / calibration |

#### TaskState

See Chapter 6, Section 6.1 for state machine semantics.

| Value | Number | Description |
|-------|--------|-------------|
| `TASK_STATE_UNSPECIFIED` | 0 | Default / unknown |
| `TASK_STATE_PENDING` | 1 | WorkOrder dispatched, awaiting ack |
| `TASK_STATE_ACCEPTED` | 2 | Machine accepted, preparing |
| `TASK_STATE_RUNNING` | 3 | Actively executing |
| `TASK_STATE_BLOCKED` | 4 | Temporarily suspended |
| `TASK_STATE_SUCCEEDED` | 5 | Completed successfully |
| `TASK_STATE_FAILED` | 6 | Failed, unrecoverable |
| `TASK_STATE_CANCELLED` | 7 | Cancelled by Site Agent |
| `TASK_STATE_REJECTED` | 8 | Rejected by Machine Agent |
| `TASK_STATE_EXPIRED` | 9 | Response window elapsed |

#### FaultSeverity

| Value | Number | Description |
|-------|--------|-------------|
| `FAULT_SEVERITY_UNSPECIFIED` | 0 | Default |
| `FAULT_SEVERITY_INFO` | 1 | Informational |
| `FAULT_SEVERITY_WARNING` | 2 | Warning, action may be needed |
| `FAULT_SEVERITY_ERROR` | 3 | Error, corrective action needed |
| `FAULT_SEVERITY_CRITICAL` | 4 | Critical, immediate action required |

### 7.1.2 Messages

#### KeyValue

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `key` | string | 1 | Key name |
| `value` | string | 2 | Value as string |

#### MessageHeader

Attached to every CapFrame. Provides tracing and correlation.

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `message_id` | string | 1 | MUST | UUID v4, unique per message |
| `sender_id` | string | 2 | MUST | ID of the sending agent |
| `receiver_id` | string | 3 | SHOULD | ID of the intended recipient |
| `correlation_id` | string | 4 | SHOULD | Links request to response |
| `work_package_id` | string | 5 | SHOULD | Groups related tasks |
| `plan_hash` | string | 6 | SHOULD | SHA-256 hash of the GoalSpec |
| `sent_at` | Timestamp | 7 | MUST | When the message was created |

#### Pose3D

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `x`, `y`, `z` | double | 1-3 | Position in meters |
| `roll`, `pitch`, `yaw` | double | 4-6 | Orientation in radians |
| `frame_id` | string | 7 | Coordinate frame reference |

#### GeoZoneRef

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `map_id` | string | 1 | Map identifier |
| `zone_id` | string | 2 | Zone identifier |
| `revision` | string | 3 | Map revision (for consistency) |

#### Constraint

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `constraint_id` | string | 1 | Unique constraint identifier |
| `type` | string | 2 | Constraint type (e.g., "KEEP_OUT", "MAX_SPEED") |
| `params` | repeated KeyValue | 3 | Constraint parameters |

#### TimeWindow

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `earliest` | Timestamp | 1 | Window start |
| `latest` | Timestamp | 2 | Window end / deadline |

---

## 7.2 Site Agent Messages (`site_agent.proto`)

Direction: **Site Agent → Machine Agent**

### WorkOrder

Task assignment to a specific machine.

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `task_id` | string | 1 | MUST | Unique task identifier |
| `work_package_id` | string | 2 | MUST | Parent work package |
| `target_machine_id` | string | 3 | MUST | Assigned machine |
| `skill` | string | 4 | MUST | Skill to execute (must match CapabilityManifest) |
| `target_zone` | GeoZoneRef | 5 | SHOULD | Primary work zone |
| `source_zone` | GeoZoneRef | 6 | MAY | Source zone (for excavation) |
| `destination_zone` | GeoZoneRef | 7 | MAY | Destination zone (for hauling) |
| `parameters` | map\<string, string\> | 8 | MAY | Skill-specific parameters |
| `preconditions` | repeated Constraint | 9 | MAY | Conditions that must be true before execution |
| `safety_constraints` | repeated Constraint | 10 | MAY | Safety constraints during execution |
| `execution_window` | TimeWindow | 11 | SHOULD | Time window for execution |
| `priority` | int32 | 12 | MAY | Priority (higher = more urgent) |

### CancelWorkOrder

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `task_id` | string | 1 | MUST | Task to cancel |
| `reason` | string | 2 | SHOULD | Cancellation reason |

### ReservationRequest

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `reservation_id` | string | 1 | MUST | Unique reservation ID |
| `resource_id` | string | 2 | MUST | Resource to reserve |
| `holder_id` | string | 3 | MUST | Requesting machine |
| `requested_window` | TimeWindow | 4 | SHOULD | Requested reservation period |
| `reason` | string | 5 | MAY | Reason for reservation |

### ReservationRelease

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `reservation_id` | string | 1 | MUST | Reservation to release |
| `reason` | string | 2 | MAY | Release reason |

### ModeCommand

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Target machine |
| `requested_mode` | MachineMode | 2 | MUST | Target mode |
| `reason` | string | 3 | SHOULD | Reason for mode change |

---

## 7.3 Machine Agent Messages (`machine_agent.proto`)

Direction: **Machine Agent → Site Agent**

### Capability

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `skill` | string | 1 | Skill name (e.g., "excavate_batch") |
| `limits` | repeated KeyValue | 2 | Skill limits (e.g., max_reach_m=10) |

### CapabilityManifest

First message in any CAP stream. Declares machine identity and capabilities.

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Unique machine identifier |
| `machine_type` | MachineType | 2 | MUST | Machine type |
| `capabilities` | repeated Capability | 3 | MUST | Available skills |
| `current_mode` | MachineMode | 4 | MUST | Current operating mode |
| `hal_profile` | string | 5 | SHOULD | HAL implementation (e.g., "komatsu/pc200-11") |
| `software_version` | string | 6 | SHOULD | Agent software version |
| `metadata` | repeated KeyValue | 7 | MAY | Additional metadata |
| `alo_descriptor` | ALODescriptor | 8 | SHOULD | Machine's ALO self-description |

### Heartbeat

Periodic health report. MUST be sent every `heartbeat_interval` (default 5s).

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Machine identifier |
| `current_mode` | MachineMode | 2 | MUST | Current mode |
| `healthy` | bool | 3 | MUST | Overall health status |
| `active_task_id` | string | 4 | SHOULD | Currently executing task |
| `active_task_state` | TaskState | 5 | SHOULD | Current task state |
| `pose` | Pose3D | 6 | SHOULD | Current position and orientation |
| `estop_active` | bool | 7 | MUST | Whether E-stop is active |
| `fuel_or_battery_percent` | double | 8 | SHOULD | Fuel/battery level (0.0–100.0) |
| `active_reservations` | repeated string | 9 | MAY | Held reservation IDs |
| `health` | repeated KeyValue | 10 | MAY | Detailed health metrics |
| `alo_state_summary` | string | 11 | MAY | LLM-generated natural language state description |

### WorkOrderAck

Response to a received WorkOrder.

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `task_id` | string | 1 | MUST | Referenced task |
| `decision` | Decision | 2 | MUST | ACCEPTED / REJECTED / DEFERRED |
| `reason` | string | 3 | SHOULD (MUST if REJECTED) | Decision reason |
| `retry_after_sec` | int32 | 4 | SHOULD (if DEFERRED) | Suggested retry delay |

---

## 7.4 Event Messages (`events.proto`)

Direction: **Machine Agent → Site Agent** (except ReservationStatus: Site → Machine)

### ProgressEvent

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Reporting machine |
| `task_id` | string | 2 | MUST | Task being reported |
| `state` | TaskState | 3 | MUST | Current task state |
| `completion_ratio` | double | 4 | MUST | 0.0 to 1.0 |
| `summary` | string | 5 | SHOULD | Human-readable summary |
| `current_zone` | GeoZoneRef | 6 | MAY | Zone where work is happening |
| `metrics` | repeated KeyValue | 7 | MAY | Task-specific metrics |

### FaultEvent

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Machine reporting fault |
| `task_id` | string | 2 | SHOULD | Affected task |
| `severity` | FaultSeverity | 3 | MUST | Fault severity |
| `fault_code` | string | 4 | MUST | Machine-readable fault code |
| `summary` | string | 5 | MUST | Human-readable description |
| `requires_handover` | bool | 6 | MUST | Whether handover to operator is needed |
| `requires_safe_stop` | bool | 7 | MUST | Whether safe stop is needed |
| `attributes` | repeated KeyValue | 8 | MAY | Additional details |

### HandoverEvent

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Machine requesting handover |
| `task_id` | string | 2 | SHOULD | Affected task |
| `requested_mode` | MachineMode | 3 | MUST | Desired mode |
| `reason` | string | 4 | MUST | Reason for handover |
| `operator_required` | bool | 5 | MUST | Whether human operator is needed |
| `response_window` | TimeWindow | 6 | MUST | Time limit for response |

### SafetyEvent

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Machine reporting |
| `task_id` | string | 2 | SHOULD | Affected task |
| `event_type` | string | 3 | MUST | Event type (e.g., "geofence_violation", "human_detected") |
| `severity` | FaultSeverity | 4 | MUST | Severity |
| `summary` | string | 5 | MUST | Human-readable description |
| `affected_zone` | GeoZoneRef | 6 | SHOULD | Zone where event occurred |
| `motion_inhibited` | bool | 7 | MUST | Whether motion is currently inhibited |

### ReservationStatus

Direction: **Site Agent → Machine Agent**

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `reservation_id` | string | 1 | MUST | Reservation identifier |
| `resource_id` | string | 2 | MUST | Reserved resource |
| `holder_id` | string | 3 | MUST | Reservation holder |
| `state` | ReservationState | 4 | MUST | Current state |
| `reason` | string | 5 | SHOULD (MUST if DENIED) | State reason |
| `granted_window` | TimeWindow | 6 | MUST (if GRANTED) | Granted time window |

### AuditEvent

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `actor_id` | string | 1 | MUST | Who performed the action |
| `subject_id` | string | 2 | MUST | What was acted upon |
| `subject_type` | string | 3 | SHOULD | Subject type (e.g., "task", "machine") |
| `action` | string | 4 | MUST | Action performed |
| `result` | string | 5 | MUST | Action result |
| `reason` | string | 6 | SHOULD | Reason for action |
| `attributes` | repeated KeyValue | 7 | MAY | Additional context |

---

## 7.5 Error Messages (`error.proto`)

### CapError

See Chapter 8 for error handling semantics.

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `error_code` | uint32 | 1 | MUST | Numeric error code (see §8.2) |
| `domain` | ErrorDomain | 2 | MUST | Error domain classification |
| `message` | string | 3 | MUST | Human-readable description |
| `related_message_id` | string | 4 | SHOULD | message_id of triggering frame |
| `severity` | FaultSeverity | 5 | MUST | Error severity |
| `details` | repeated KeyValue | 6 | MAY | Machine-readable details |
| `retryable` | bool | 7 | MUST | Whether retry is possible |
| `retry_after_sec` | int32 | 8 | SHOULD (if retryable) | Suggested retry delay |

---

## 7.6 ALO Messages (`alo.proto`)

### ALODescriptor

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `alo_id` | string | 1 | MUST | Globally unique identifier |
| `alo_type` | string | 2 | MUST | Entity type ("zone", "machine", "material", etc.) |
| `canonical_name` | string | 3 | MUST | Human-readable name |
| `properties` | repeated ALOProperty | 4 | SHOULD | Typed attributes |
| `sub_objects` | repeated ALOSubObject | 5 | MAY | Component entities |
| `state_description` | string | 6 | SHOULD | Natural language state |
| `manager` | ALOManager | 7 | SHOULD | Capabilities and knowledge |
| `updated_at` | Timestamp | 8 | MUST | Last update time |
| `owner_agent_id` | string | 9 | MUST | Maintaining agent |

### ALOProperty

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `key` | string | 1 | Property name |
| `value` | string | 2 | Property value |
| `unit` | string | 3 | Unit of measurement (empty if N/A) |
| `dtype` | string | 4 | Data type ("float", "string", "int", "bool", "enum") |

### ALOSubObject

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `sub_obj_id` | string | 1 | Sub-object identifier |
| `sub_obj_type` | string | 2 | Sub-object type |
| `description` | string | 3 | Natural language description |
| `properties` | repeated ALOProperty | 4 | Sub-object properties |

### ALOManager

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `available_skills` | repeated string | 1 | Skills this entity can perform |
| `interaction_rules` | repeated string | 2 | Natural language interaction rules |
| `relations` | repeated ALORelation | 3 | Relationships to other ALOs |
| `state_transition_rules` | repeated string | 4 | State transition descriptions |
| `current_knowledge` | repeated string | 5 | Domain knowledge |

### ALORelation

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `relation_type` | string | 1 | Relationship type |
| `target_alo_id` | string | 2 | Related ALO |
| `description` | string | 3 | Natural language description |

### ALOStateUpdate

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Sending machine |
| `alo` | ALODescriptor | 2 | MUST | Updated ALO descriptor |
| `update_reason` | string | 3 | SHOULD | Reason ("periodic", "state_change", "anomaly_detected") |

### ALOInteraction

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `interaction_id` | string | 1 | MUST | Unique interaction ID |
| `initiator_alo_id` | string | 2 | MUST | Initiating entity |
| `target_alo_id` | string | 3 | MUST | Target entity |
| `interaction_type` | string | 4 | MUST | Interaction type (e.g., "excavate") |
| `description` | string | 5 | SHOULD | Natural language description |
| `parameters` | repeated KeyValue | 6 | MAY | Interaction parameters |
| `timestamp` | Timestamp | 7 | MUST | When the interaction occurred |

---

## 7.7 Dialogue Messages (`dialogue.proto`)

### DialogueProvenance

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `agent_id` | string | 1 | MUST | Generating agent |
| `agent_role` | string | 2 | MUST | "machine_agent" or "site_agent" |
| `confidence` | double | 3 | SHOULD | Confidence score 0.0–1.0 |
| `model_id` | string | 4 | SHOULD | Model identifier |
| `generated_at` | Timestamp | 5 | MUST | Generation timestamp |
| `reasoning_summary` | string | 6 | MAY | Brief reasoning explanation |

### SituationReport

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Reporting machine |
| `task_id` | string | 2 | SHOULD | Related task |
| `situation_summary` | string | 3 | MUST | Natural language situation |
| `observed_facts` | repeated ALOProperty | 4 | SHOULD | Structured observations |
| `recommended_action` | string | 5 | MAY | Suggested action |
| `provenance` | DialogueProvenance | 6 | MUST | Origin metadata |

### LocalDecision

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Deciding machine |
| `task_id` | string | 2 | SHOULD | Related task |
| `scope` | LocalDecisionScope | 3 | MUST | Decision scope |
| `decision_summary` | string | 4 | MUST | What was decided |
| `rationale` | string | 5 | SHOULD | Why this decision |
| `approval_required` | bool | 6 | MUST | True if scope ≥ TASK |
| `approved` | bool | 7 | — | Set by Site Agent in response |
| `approver_id` | string | 8 | — | Approver identity |
| `provenance` | DialogueProvenance | 9 | MUST | Origin metadata |

### PlanProposal

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `machine_id` | string | 1 | MUST | Proposing machine |
| `task_id` | string | 2 | SHOULD | Related task |
| `proposal_summary` | string | 3 | MUST | What is proposed |
| `proposed_parameters` | repeated KeyValue | 4 | SHOULD | Parameter changes |
| `expected_outcome` | string | 5 | MAY | Expected result |
| `provenance` | DialogueProvenance | 6 | MUST | Origin metadata |

### DialogueMessage

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `message_id` | string | 1 | MUST | Unique message ID |
| `intent` | DialogueIntent | 2 | MUST | Message purpose |
| `content` | oneof | 10-13 | MUST | One of: SituationReport, LocalDecision, PlanProposal, text |
| `provenance` | DialogueProvenance | 14 | MUST | Origin metadata |
| `timestamp` | Timestamp | 15 | MUST | Message timestamp |

### AgentDialogue

| Field | Type | Number | Required | Description |
|-------|------|--------|----------|-------------|
| `dialogue_id` | string | 1 | MUST | Unique dialogue ID |
| `participant_ids` | repeated string | 2 | MUST | Participating agent IDs |
| `task_id` | string | 3 | SHOULD | Related task |
| `messages` | repeated DialogueMessage | 4 | MUST | Dialogue messages |
| `created_at` | Timestamp | 5 | MUST | Dialogue creation time |

---

## 7.8 Runtime Messages (`runtime.proto`)

### CapFrame

Universal message envelope.

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `header` | MessageHeader | 1 | Message metadata |
| `body` | oneof | 10-50 | Exactly one message body (see field numbers in §7.8.1) |

#### 7.8.1 CapFrame Body Field Numbers

| Field Number | Body Type | Direction |
|-------------|-----------|-----------|
| 10 | WorkOrder | Site → Machine |
| 11 | CancelWorkOrder | Site → Machine |
| 12 | ReservationRequest | Site → Machine |
| 13 | ReservationRelease | Site → Machine |
| 14 | ModeCommand | Site → Machine |
| 20 | CapabilityManifest | Machine → Site |
| 21 | Heartbeat | Machine → Site |
| 22 | WorkOrderAck | Machine → Site |
| 30 | ReservationStatus | Site → Machine |
| 31 | ProgressEvent | Machine → Site |
| 32 | FaultEvent | Machine → Site |
| 33 | HandoverEvent | Machine → Site |
| 34 | SafetyEvent | Machine → Site |
| 35 | AuditEvent | Either |
| 40 | ALOStateUpdate | Machine → Site |
| 41 | ALOInteraction | Either |
| 42 | AgentDialogue | Either |
| 50 | CapError | Either |

### ConnectRequest

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `frame` | CapFrame | 1 | Message payload |
| `supported_versions` | repeated string | 2 | Protocol versions (first message only) |

### ConnectResponse

| Field | Type | Number | Description |
|-------|------|--------|-------------|
| `frame` | CapFrame | 1 | Message payload |
| `negotiated_version` | string | 2 | Selected protocol version (first response only) |
