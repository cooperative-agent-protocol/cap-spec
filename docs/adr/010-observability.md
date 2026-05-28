<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-010: Observability — OpenTelemetry Semantic Conventions for CAP

**Status:** Accepted
**Date:** 2026-05-26
**Context:** Pre-public-release (Phase 0)

## Decision

CAP adopts **OpenTelemetry (OTel)** as the recommended observability stack for
implementations and standardizes a set of **semantic convention attributes** for
CAP-specific traces, metrics, and logs. Implementations are not required to use
OpenTelemetry, but if they emit traces / metrics / logs, they MUST use the
attribute names defined here (or be free to extend with additional attributes
under the `cap.*` namespace).

This ADR is a normative reference for the observability layer. Implementations
that emit telemetry with conflicting attribute names will not be considered
conformant at Conformance Level 2+.

## Context

LLM-driven industrial coordination is intrinsically debugging-heavy. Multi-agent
state mismatches, model hallucinations, and timing-related deadlocks are hard to
reproduce without strong observability. Without a standard, every implementation
defines its own attribute names (`cap.task.id` vs `cap.work_order_id` vs
`task_uuid`), making cross-impl analysis impossible.

OpenTelemetry is the de facto standard for OSS observability and has a strong
semantic conventions process. Following the OTel pattern aligns CAP with the
broader cloud-native ecosystem and reuses tooling investments (Grafana, Honeycomb,
Datadog, AWS X-Ray, etc.).

## Attribute namespace

All CAP-specific attributes use the `cap.*` prefix:

| Attribute | Type | Cardinality | Description |
|---|---|---|---|
| `cap.protocol_version` | string | low | Proto package version, e.g. `cap.v0.core`. |
| `cap.domain` | string | low | Active Domain Pack name, e.g. `construction`, `agriculture`. Absent → core-only operation. |
| `cap.machine.id` | string | high | Machine identifier (`zx120-01` etc.). Pinned to the lifetime of the connection. |
| `cap.machine.type` | string | low | Enum from `MachineType` (e.g. `excavator`, `dump_truck`). |
| `cap.site.id` | string | high | Site Agent identifier. |
| `cap.work_order.id` | string | high | WorkOrder UUID. |
| `cap.work_order.skill` | string | low | Skill name (e.g. `construction.excavate_batch`). |
| `cap.task.id` | string | high | TaskGraph node id, when applicable. |
| `cap.task.state` | string | low | TaskState enum (`PENDING`, `RUNNING`, `SUCCEEDED`, etc.). |
| `cap.intent.kind` | string | low | DialogueIntent enum value. |
| `cap.dialogue.id` | string | high | Dialogue thread identifier. |
| `cap.reservation.id` | string | high | Reservation UUID. |
| `cap.reservation.holder` | string | high | Machine id holding the reservation. |
| `cap.handover.from_mode` | string | low | MachineMode before handover. |
| `cap.handover.to_mode` | string | low | MachineMode after handover. |
| `cap.error.code` | string | low | `CapError.code` enum value. |
| `cap.error.domain` | string | low | `ErrorDomain` enum value. |
| `cap.transport` | string | low | `grpc` \| `mqtt` \| `websocket`. |
| `cap.layer` | string | low | `site_agent` \| `machine_agent` \| `safety_supervisor`. |
| `cap.command.id` | string | high | CommandHandle UUID for low-level intent dispatch. |
| `cap.plan.id` | string | high | PlanContract id. |
| `cap.plan.world_seq` | int | high | Plan world-model sequence number. |

Cardinality column reminds implementers which attributes are safe to use as
labels for high-cardinality metrics backends (low) vs trace-only (high).

## Span naming convention

Spans follow the OpenTelemetry pattern of `<verb>.<noun>` snake_case:

| Span name | Layer | Notes |
|---|---|---|
| `cap.work_order.dispatch` | Site Agent | Around emit of a WorkOrder; child of the originating instruction span. |
| `cap.work_order.receive` | Machine Agent | Receipt of a WorkOrder; child of the gRPC server span. |
| `cap.work_order.execute` | Machine Agent | End-to-end execution of one WorkOrder; spans the entire task. |
| `cap.skill.execute` | Machine Agent | One skill invocation within a WorkOrder. |
| `cap.skill.precondition_check` | Machine Agent | Precondition evaluation. |
| `cap.skill.effect_verification` | Machine Agent | Effect (postcondition) verification. |
| `cap.heartbeat.emit` | Machine Agent | Each heartbeat tick (sampling recommended). |
| `cap.dialogue.exchange` | Site / Machine | One dialogue round-trip. |
| `cap.dialogue.llm_inference` | either | Wrapping the LLM call itself. |
| `cap.intent.dispatch` | Machine Agent | Low-level intent dispatch via CommandDispatcher. |
| `cap.plan.compute` | Machine Agent | Plan compute (Hybrid A* or equivalent). |
| `cap.safety.abort` | Safety Supervisor | Safety abort event. |
| `cap.reservation.acquire` | either | Reservation request. |
| `cap.handover.execute` | Machine Agent | Mode handover. |

Implementations may add additional spans under the `cap.*` namespace.

## Metrics

Recommended metrics with their semantic conventions:

| Metric | Type | Unit | Attributes | Description |
|---|---|---|---|---|
| `cap.heartbeat.latency` | histogram | seconds | `cap.machine.id`, `cap.transport` | End-to-end heartbeat round-trip. |
| `cap.work_order.duration` | histogram | seconds | `cap.machine.id`, `cap.work_order.skill`, terminal `cap.task.state` | WorkOrder duration. |
| `cap.dialogue.llm_latency` | histogram | seconds | `cap.layer`, model id | LLM inference latency. |
| `cap.safety.abort.count` | counter | 1 | `cap.machine.id`, abort cause | Number of safety aborts. |
| `cap.reservation.queue_depth` | gauge | 1 | resource id | Pending reservations. |
| `cap.frame.send.count` | counter | 1 | `cap.layer`, `cap.transport`, body kind | CapFrame sends. |
| `cap.frame.receive.count` | counter | 1 | `cap.layer`, `cap.transport`, body kind | CapFrame receives. |

## Logs

Logs that correspond to a CAP event (e.g., WorkOrder rejection, safety abort)
should include the relevant `cap.*` attributes at the log record level so they
can be correlated with traces.

Structured logging is strongly recommended (JSON or OTel log protocol).

## Resource attributes

In addition to standard OTel resource attributes (`service.name`, `host.name`),
implementations should set:

| Resource attribute | Description |
|---|---|
| `cap.protocol_version` | Same as the span attribute, but at the resource level so it propagates to all telemetry. |
| `cap.sdk.name` | e.g. `cap-sdk-python`, `cap-sdk-cpp`. |
| `cap.sdk.version` | SDK SemVer. |
| `cap.agent.role` | `site` \| `machine` \| `safety_supervisor`. |
| `cap.domain` | Domain Pack name if active. |

## Rationale

- **Cross-impl analysis**: a single Grafana dashboard works regardless of
  whether the implementation is Python, C++, or someone's proprietary Java
  stack.
- **Industrial alignment**: OEMs already use Grafana / Splunk / Datadog
  internally. Mapping CAP telemetry into their existing dashboards is
  drop-in.
- **Future Domain Packs**: the `cap.domain` attribute lets aggregations
  separate construction-site traces from agriculture-field traces without
  per-deployment configuration.

## Consequences

- The reference SDK should ship optional OTel instrumentation (e.g.
  `cap-sdk-python[otel]` extra). v0.1.0 spec defines the conventions; v0.2.0
  SDKs add the instrumentation. Conformance Level 2 will require the
  attributes to be set correctly on emitted telemetry.
- Adding a new attribute requires a MINOR `cap-spec` bump and an RFC.
  Renaming or removing an attribute requires a MAJOR bump.
- A future ADR may define a dedicated `cap-otel-collector-config` repository
  with curated dashboards.

## References

- OpenTelemetry semantic conventions:
  <https://opentelemetry.io/docs/specs/semconv/>
- OTel resource conventions:
  <https://opentelemetry.io/docs/specs/semconv/resource/>
- Google Cloud Trace attribute conventions (similar layering pattern):
  <https://cloud.google.com/trace/docs/setup>
- ADR-002 (Transport-Neutral Semantics)
- ADR-007 (Formal Verification) — TLA+ model assertions can be used as
  test oracles for telemetry sampling decisions.
