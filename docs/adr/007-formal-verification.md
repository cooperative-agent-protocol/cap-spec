<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-007: Formal Verification of State Machines

**Status:** Accepted
**Date:** 2026-03-20
**Context:** M3.8 — Protocol Hardening

## Decision

All normative state machines defined in Chapter 6 of the CAP specification are
formally modeled in TLA+ and verified using the TLC model checker.

## Context

CAP defines five state machines (TaskState, MachineMode, ReservationState,
HandoverEvent flow, DialogueFlow) whose correct interaction is safety-critical.
Informal specification through Mermaid diagrams and transition tables is
insufficient to guarantee the absence of deadlocks, double-grants, or starvation
in multi-machine coordination scenarios.

Protocols like VDA 5050 and MCP do not provide formal verification of their
state machines. This is a key differentiator for CAP, particularly in the
construction domain where safety properties must be demonstrable.

## Models

| Model | File | Properties Verified |
|-------|------|-------------------|
| TaskState | `formal/tla/TaskState.tla` | Terminal states absorbing, at most one active task, eventual termination |
| ReservationState | `formal/tla/ReservationState.tla` | No double-grant, holder consistency, eventual decision |
| MachineMode + Handover | `formal/tla/MachineMode.tla` | SAFE_STOP reachability, handover timeout → SAFE_STOP, handover resolution |
| Multi-machine Coordination | `formal/tla/CAPCoordination.tla` | No deadlock, no starvation, no double-grant (2 excavators + 1 dump competing for load point) |

## Rationale

**Why TLA+?**
- Industry standard for protocol verification (used by AWS, Azure, Intel)
- TLC model checker provides exhaustive state space exploration
- Readable by non-specialists (closer to mathematical notation than code)
- Well-suited for asynchronous distributed protocols

**Why not Alloy, SPIN, or Promela?**
- TLA+ has broader adoption in industry protocol verification
- TLA+ handles fairness and liveness properties naturally
- The CAP state machines are conceptually clean enough to not need Alloy's relational modeling
- TLC can check both safety and liveness properties

## Consequences

- All state machine changes in Chapter 6 MUST be reflected in the TLA+ models
- CI should run TLC verification on proto/spec changes (when TLC is available)
- The formal models serve as executable specification alongside the prose spec
- Results can be cited in publications as evidence of protocol correctness

## Verification Results

To verify locally:

```bash
# Requires TLA+ tools (https://github.com/tlaplus/tlaplus)
cd cap-spec/formal/tla/
java -jar tla2tools.jar -config TaskState.cfg TaskState.tla
java -jar tla2tools.jar -config ReservationState.cfg ReservationState.tla
java -jar tla2tools.jar -config MachineMode.cfg MachineMode.tla
java -jar tla2tools.jar -config CAPCoordination.cfg CAPCoordination.tla
```

All models should report: "Model checking completed. No error has been found."
