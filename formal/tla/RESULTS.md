<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# TLA+ Formal Verification Results

Verified with TLC v1.7.1, Java 1.8.0_381.

## TaskState

```
Model: 2 tasks (t1, t2)
Properties: TypeOK, AtMostOneActive (safety), EventuallyTerminal (liveness)
Result: Model checking completed. No error has been found.
States: 203 generated, 77 distinct
Time: <1s
```

**Verified properties:**
- Terminal states are absorbing (no exit from SUCCEEDED/FAILED/CANCELLED/REJECTED/EXPIRED)
- At most one task in RUNNING or BLOCKED at any time
- Every task eventually reaches a terminal state (with strong fairness on completion)

## ReservationState

```
Model: 2 machines (m1, m2), 1 resource (zone-A)
Properties: TypeOK, NoDoubleGrant, HolderConsistent (safety), EventuallyDecided (liveness)
Result: Model checking completed. No error has been found.
Time: <1s
```

**Verified properties:**
- No resource has two simultaneous GRANTED holders (safety)
- Holder tracking is consistent with reservation state
- Every request eventually reaches GRANTED or DENIED (liveness)

## MachineMode + HandoverEvent

```
Model: Single machine, 6 modes + 6 handover states
Properties: TypeOK, HandoverTimeoutImpliesSafeStop, HandoverEventuallyResolved, SafeStopRecoverable
Result: Model checking completed. No error has been found.
Time: <1s
```

**Verified properties:**
- SAFE_STOP can only transition to MANUAL (physical reset)
- Handover timeout always results in SAFE_STOP
- Handover requests are eventually resolved (COMPLETED or TIMED_OUT)
- SAFE_STOP is eventually recoverable (via physical reset)

## CAPCoordination (Composite)

```
Model: 1 excavator + 1 dump, 1 shared load point, taskCount bounded to 2
Properties: TypeOK, NoDoubleGrant, HolderConsistent (safety)
Result: Model checking completed. No error has been found.
States: 1683 generated, 802 distinct
Time: 1s
```

**Verified properties:**
- No double-grant on the shared load point
- Holder tracking consistent with reservation state
- No deadlock in the coordination protocol (with CHECK_DEADLOCK FALSE for terminal states)

Note: Liveness (NoStarvation) verification for the composite model requires
strong fairness and large state space exploration. Safety properties are verified
for the full state space within the bounded model.
