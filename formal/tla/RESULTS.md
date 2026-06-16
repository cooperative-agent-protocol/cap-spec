<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# TLA+ Formal Verification Results

**Toolchain.** TLC 2 version 2026.05.26 (`tla2tools.jar` v1.8.0,
sha256 `237332bdcc79a35c7d26efa7b82c77c85c2744591c5598673a8a45085ff2a4fb`)
on Eclipse Temurin 21.0.5+11 (LTS), Apple Silicon (arm64), macOS.
All runs are reproduced by `./run_sweep.sh` (which verifies the jar digest,
runs every configuration below, and asserts each verdict against its
expected outcome — the negative results are first-class and a silent flip
in either direction fails the script). Per-run logs are written to `logs/`.

The composite model `CAPCoordination` is parameterised over machine sets
(`Excavators`, `Dumps`), a resource set (`Resources`), a saturating
per-machine task counter (`MaxTasks`), and a `QueuedGrants` boolean that
selects the reservation regime (deny-on-busy vs. queue-on-busy). The
per-machine counter saturates rather than growing without bound, so the
state space is finite **without** a state constraint; this makes liveness
checking sound (TLC liveness under a state constraint is unsound).

---

## Component specifications

### TaskState
```
Model:      2 tasks (t1, t2)
Properties: TypeOK, AtMostOneActive (safety), EventuallyTerminal (liveness)
Result:     No error has been found.
States:     203 generated, 77 distinct
```
Terminal states are absorbing; at most one task is active at a time; every
task eventually terminates (strong fairness on completion).

### ReservationState
N machines competing for M resources; `EnableTimeouts` gates `DenyTimeout`
and `ExpireGrant`.

| Config | Spec | EnableTimeouts | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|---|
| `ReservationState.cfg` | weak-fair | TRUE | TypeOK, NoDoubleGrant, HolderConsistent, EventuallyDecided | **holds** | 93 / 35 |
| `ReservationState_notimeout.cfg` | weak-fair | FALSE | EventuallyDecided | **violated** | 47 / 23 |
| `ReservationState_notimeout_strong.cfg` | strong-fair | FALSE | EventuallyDecided | **holds** | 47 / 23 |

**Finding (request resolution).** With timeouts disabled and only weak
fairness, `EventuallyDecided` is *violated*: the published liveness result
relies on `DenyTimeout`'s weak fairness. Counterexample lasso (m2 starves
while m1 cycles grant→release→re-request):
```
Request(m2) ; Request(m1) ; Grant(m1) ; Release(m1) ; [back to Request(m2)] ...
```
Under a **strongly fair** grant/deny arbiter the property holds again, with
no timeouts. So request resolution requires *either* timeouts (the current
protocol) *or* a strongly fair site agent — both regimes are verified.

### MachineMode + HandoverEvent
Six modes + six handover states; `EnableFaults` gates `SafetyTrigger` and
`HandoverTimeout`.

| Config | EnableFaults | Properties | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `MachineMode.cfg` | TRUE | TypeOK, HandoverTimeoutImpliesSafeStop, HandoverEventuallyResolved, SafeStopRecoverable | **holds** | 38 / 14 |
| `MachineMode_nofault.cfg` | FALSE | HandoverCompletesWithoutFaults, HandoverEventuallyResolved | **holds** | 17 / 11 |

**Finding (productive progress, P3b).** With faults disabled, a requested
handover always reaches `COMPLETED` through the
acknowledge → mode-command → complete path
(`HandoverCompletesWithoutFaults`). Handover progress therefore does not
depend on the timeout/`SafeStop` escape — it answers the objection that
"progress is trivial because a timeout always fires."

### ReservationFencing (adversarial delivery + fencing token)

The composite assumes reliable, ordered delivery. This component drops that
assumption: the arbiter can reclaim a resource (grant window elapsed /
preemption) while the expiry/release notification to the holder is **lost**, so
the holder keeps believing it holds the resource. `Fenced` selects whether a
monotonic per-resource grant epoch (a Chubby/ZooKeeper-style fencing token) is
enforced on actuation.

| Config | Fenced | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `ReservationFencing_fenced.cfg` | TRUE | TypeOK, ExclusiveActuation | **holds** | 95 / 55 |
| `ReservationFencing_unfenced.cfg` | FALSE | ExclusiveActuation | **violated** | 4-state counterexample |

**Finding (fencing is load-bearing under lost delivery).** Without the token,
`ExclusiveActuation` is violated by a 4-state behavior:
```
Grant(m1, LP-1)          ; m1 believes LP-1, token 1, arbEpoch 1
ExpireLostNotify(LP-1)   ; arbiter reclaims LP-1; m1's notification is LOST (still believes)
Grant(m2, LP-1)          ; m2 believes LP-1, token 2, arbEpoch 2
→ both m1 (stale, token 1) and m2 (fresh, token 2) act as holder of LP-1.
```
With `Fenced = TRUE` a machine may act only while `token[m] = arbEpoch[r]`, so
the stale holder (token 1 ≠ epoch 2) cannot act and `ExclusiveActuation`
holds. This is the model-checked counterpart of the fault-injection campaign's
empirical result that a dropped `ReservationStatus` causes exclusivity
violations without arbitration: the *protocol-level* fix is a fencing token on
the grant, which the composite's reliable-delivery abstraction cannot see.

### SafetySupervisor (independent Layer-C non-interference)

CAP's central architectural claim is that safety is **decoupled** from the LLM
and the coordination protocol (ADR-003): a deterministic Safety Supervisor can
inhibit actuation in any interleaving and its inhibit has priority over any
protocol authorization. This component models the supervisor as an independent
process racing the protocol, so the decoupling becomes a checkable
non-interference invariant `InhibitStops` (`inhibit[m] ⇒ op[m] = STOPPED`).
The protocol/LLM layer is deliberately unaware of the safety channel (it may
authorize while inhibited), so safety cannot rest on its cooperation.

| Config | SupervisorPriority | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `SafetySupervisor_priority.cfg` | TRUE | TypeOK, InhibitStops | **holds** | 121 / 25 |
| `SafetySupervisor_nopriority.cfg` | FALSE | InhibitStops | **violated** | 4-state counterexample |

**Finding (safety decoupling requires supervisor priority).** With
`SupervisorPriority = TRUE` — actuation gated by `~inhibit` and an inhibit
forcing an immediate stop in the same step — `InhibitStops` **holds** across
every interleaving of the protocol and the supervisor. Without priority it is
**violated** by a 4-state behavior:
```
ProtocolAuthorize(m1) ; StartMove(m1)        ; m1 MOVING
SupervisorInhibit(m1)                          ; inhibit[m1] = TRUE but op[m1] stays MOVING
→ m1 is inhibited AND actuating.
```
So the architecture's safety guarantee is not free from the layering: it
holds **iff** the Layer-C supervisor has priority over the protocol and the
authority to stop actuation deterministically. This is the verified form of
the paper's "LLM-independent safety supervisor" thesis.

### MultiResource (hold-and-wait deadlock + acquisition order)

`CAPCoordination` tracks one outstanding reservation per machine, so it is
*structurally* deadlock-free and `CHECK_DEADLOCK` over it is a tautology. This
component models genuine multi-resource **hold-and-wait** — every machine needs
the whole resource set and acquires resources one at a time — so circular-wait
deadlock is expressible. `ResourceOrder` selects the discipline.

| Config | ResourceOrder | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `MultiResource_ordered.cfg` | TRUE | TypeOK, HoldsOwnerConsistent, NoDoubleOwner, `CHECK_DEADLOCK` | **holds** (deadlock-free) | 7 / 5 |
| `MultiResource_unordered.cfg` | FALSE | (same) | **deadlock** | 3-state circular wait |

**Finding (deadlock-freedom requires an acquisition order).** Without an order,
TLC reaches a circular wait and reports a global deadlock:
```
Acquire(m1, 1) ; Acquire(m2, 2)
→ owner = (1 ↦ m1, 2 ↦ m2),  holds = (m1 ↦ {1}, m2 ↦ {2})
   m1 waits for 2 (held by m2); m2 waits for 1 (held by m1); no action enabled.
```
Enforcing a total acquisition order (a machine acquires resource `r` only once
it holds every needed resource ordered before `r`) makes the circular wait
unreachable and the model deadlock-free. Mutual exclusion (`NoDoubleOwner`,
`HoldsOwnerConsistent`) holds in both regimes — the order buys deadlock-freedom,
not exclusivity. This converts the composite's structural deadlock-freedom into
a verified property over real multi-hold contention and names the required
discipline.

---

## Composite: CAPCoordination

### Safety + deadlock sweep (no starvation/liveness)
All instances check `TypeOK`, `NoDoubleGrant`, `HolderConsistent`,
`TargetConsistent` and `CHECK_DEADLOCK TRUE` (except the regression cfg,
which mirrors the original `CHECK_DEADLOCK FALSE`). `QueuedGrants = FALSE`
(deny-based). Contention is exercised wherever machines > resources.

| Config | (|E|,|D|,|R|) | N | Symmetry | Generated | Distinct | Time | Verdict |
|---|---|---|---|---|---|---|---|
| `CAPCoordination_safety.cfg` (regression) | (1,1,1), MaxTasks≤2 | 2 | no | 1,779 | **802** | <1 s | holds |
| `CAPCoordination_N2R1.cfg` | (1,1,1) | 2 | no | 1,779 | 802 | <1 s | holds |
| `CAPCoordination_N3R1.cfg` | (2,1,1) | 3 | no | 100,768 | 30,547 | 1 s | holds |
| `CAPCoordination_N3R2.cfg` | (2,1,2) | 3 | no | 422,539 | 119,601 | 1 s | holds |
| `CAPCoordination_N4R2.cfg` | (2,2,2) | 4 | yes | 4,110,603 | 869,223 (orbit) | 5 s | holds |
| `CAPCoordination_N4R2_nosym.cfg` | (2,2,2) | 4 | no | 31,622,209 | 6,706,875 | 25 s | holds |
| `CAPCoordination_N5R2.cfg` | (3,2,2) | 5 | yes | 92,497,506 | 15,643,374 (orbit) | 2 min | holds |

No invariant violation and **no deadlock** at any instance. The model is
structurally deadlock-free (every reachable state leaves at least one
machine with an enabled action), which is *why* the meaningful progress
question is no-starvation (below), not deadlock.

**Symmetry soundness cross-check.** At (2,2,2) the symmetry-reduced run and
the full run reach the same verdict; the distinct-state ratio
6,706,875 / 869,223 ≈ 7.7 is consistent with the symmetry group
|Perm(2)×Perm(2)×Perm(2)| = 8 (slightly below 8 because some states are
fixed by a permutation). Symmetry is used for safety configs only and
never for liveness (it is unsound with liveness in TLC).

**Stop rule.** Each run is bounded by a 2 h / 8 GB budget; the sweep stops
at (3,2,2). N=6 raw is out of laptop reach and adds nothing qualitative.

### No-starvation (liveness, P3c)
No symmetry, no state constraint, `MaxTasks = 1`, strongly fair site agent
(`SpecStrong`). `QueuedGrants` selects the reservation regime.

| Config | (|E|,|D|,|R|) | QueuedGrants | Properties | Verdict | States (gen/dist) |
|---|---|---|---|---|---|---|
| `CAPCoordination_live_N2R1_retry.cfg` | (1,1,1) | FALSE | NoStarvation, AlwaysEventuallyCompletes | **violated** | 685 / 308 |
| `CAPCoordination_live_N2R1_queued.cfg` | (1,1,1) | TRUE | NoStarvation, AlwaysEventuallyCompletes | **holds** | 321 / 140 |
| `CAPCoordination_live_N3R1_queued.cfg` | (2,1,1) | TRUE | NoStarvation, AlwaysEventuallyCompletes | **holds** | 5,401 / 1,600 |
| `CAPCoordination_live_N3R2_queued.cfg` | (2,1,2) | TRUE | NoStarvation, AlwaysEventuallyCompletes | **holds** | 16,264 / 4,537 |

**Finding (no-starvation, P3c).** Deny-based reservation can *starve* a
machine even at the minimal (1,1,1) instance and even under a strongly fair
site agent: the loser of a grant is denied → blocked → retries, while the
winner completes, releases, and re-acquires before the retry lands.
Counterexample lasso (exc1's `taskCount` stays 0 forever):
```
Dispatch(exc1) ; Accept(exc1) ; Request(exc1,LP-1) ;
Dispatch(dump1) ; Accept(dump1) ; Request(dump1,LP-1) ;
Grant(dump1) ; Deny(exc1) ; CompleteTask(dump1) ; BlockOnDenial(exc1) ;
ResetTask(dump1) ; [dump1 re-acquires LP-1 ahead of exc1's retry] ...
```
Switching the site agent to **queue** requests instead of bouncing them
(`QueuedGrants = TRUE`) restores starvation-freedom: with the grant action
strongly fair, a queued request is eventually granted. Verified for
(1,1,1), (2,1,1) and (2,1,2). Liveness was checked to ~10^3–10^4 states
while safety was checked to ~10^7 states; the negative result at (1,1,1)
shows the liveness machinery has teeth at this scale.

### Handover receiver ownership (P4)

The composite now models a **machine-to-machine load-point handover** (an
excavator hands the shared load point directly to a waiting carrier rather
than completing-and-releasing it). `EnableHandover` gates the sub-protocol
and `AtomicHandover` selects the transfer discipline. The invariant
`HandoverReceiverOwnership` (P4) states that throughout a handover's
`IN_PROGRESS` window the named receiver is the **unique** grant holder of the
handed-over resource — formally,
`hoState[r] = IN_PROGRESS  =>  holder[r] = hoReceiver[r]` and no other machine
is `GRANTED` on `r`.

| Config | (\|E\|,\|D\|,\|R\|) | AtomicHandover | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|---|
| `CAPCoordination_ho_N2R1_atomic.cfg` | (1,1,1) | TRUE | + HandoverReceiverOwnership | **holds** | 441 / 204 |
| `CAPCoordination_ho_N3R1_atomic.cfg` | (2,1,1) | TRUE | + HandoverReceiverOwnership | **holds** | 9,625 / 3,088 |
| `CAPCoordination_ho_N3R1_naive.cfg` | (2,1,1) | FALSE | HandoverReceiverOwnership | **violated** | 11-state counterexample |

(The two atomic instances are exhaustive — no error — so their state counts
are deterministic; the naive instance reports the first counterexample TLC
reaches, so the exact generated/distinct count varies with worker count, but
the shortest counterexample is 11 states deep and the verdict is invariant.)

All handover configs use the queued regime (`QueuedGrants = TRUE`) so the
receiver waits in `REQUESTED` for the offer, and check `TypeOK`,
`NoDoubleGrant`, `HolderConsistent`, `TargetConsistent` alongside P4.

**Finding (handover must be atomic).** With `AtomicHandover = TRUE` the
ownership of `r` passes sender → receiver in a single step, so P4 **holds**,
including at (2,1,1) where a *third* machine (`exc2`) is simultaneously queued
for the same load point and cannot steal it. With `AtomicHandover = FALSE`
(a naive release-then-regrant) P4 is **violated**: the sender releases `r`
*before* the receiver is re-granted, so the `IN_PROGRESS` window opens with the
load point unheld. Counterexample (the violating state):
```
InitiateHandover(exc1, LP-1, exc2) ; AckHandover(LP-1) ; BeginHandoverNaive(LP-1)
→  hoState[LP-1] = "IN_PROGRESS"   (handover in progress)
   holder[LP-1]  = "NONE"          (load point unheld — receiver does not yet own it)
   resState      = [exc1 ↦ RELEASED, exc2 ↦ REQUESTED, dump1 ↦ NONE]
```
At this state a third machine can acquire `LP-1` via ordinary `GrantResource`,
so two machines could occupy the load point during the transfer. This is why
CAP specifies the handover as an **atomic ownership transfer** (the receiver
is granted in the same step the sender releases), not a release-then-regrant.
The other three safety invariants still hold under the naive regime, so the
defect is specifically a *receiver-ownership* violation, not a double-grant.

---

## Changelog (this revision)

- **Added `MultiResource`**, a hold-and-wait model over a resource set, turning
  the composite's structural (tautological) deadlock-freedom into a verified
  property: without a total acquisition order TLC reaches a circular-wait
  deadlock; with the order the model is deadlock-free. `run_sweep.sh` now also
  treats a TLC ``Deadlock reached'' as a (first-class) negative verdict.
- **Added `SafetySupervisor`**, an independent-process model of Layer C that
  races the protocol/LLM layer and verifies the non-interference invariant
  `InhibitStops` (inhibit ⇒ not actuating). Holds under supervisor priority,
  violated without it — the verified form of the "LLM-independent safety
  supervisor" thesis, and a negative result showing the decoupling requires
  Layer-C priority + immediate-stop authority.
- **Added `ReservationFencing`**, a component model of adversarial delivery
  (lost expiry/release notification → stale holder) showing that a monotonic
  grant epoch (fencing token) restores `ExclusiveActuation`: holds with the
  token, violated without it (4-state counterexample). This lifts the
  fault-injection campaign's empirical "dropped ReservationStatus →
  exclusivity violation" to a model-checked statement and names the
  protocol-level fix.
- **Composed a machine-to-machine handover into `CAPCoordination`** and added
  the P4 invariant `HandoverReceiverOwnership`, verified across atomic
  (holds, incl. with a third contender) and naive (violated) regimes. The
  reservation-only sweep is reproduced bit-for-bit: with `EnableHandover =
  FALSE` the new handover transitions are disabled and the two new variables
  (`hoState`, `hoReceiver`) stay constant, so `CAPCoordination_safety.cfg`
  still yields 802 distinct states and every prior verdict is unchanged.
- **Generalised `CAPCoordination`** from a single scalar load point to a
  resource *set* (`holder` is now a per-resource function and each machine
  tracks one outstanding `resTarget`). With `Resources = {"LP-1"}` and the
  task-count constraint, the model reproduces the original result exactly
  (**802 distinct states**); generated rose 1,683 → 1,779 because of the
  bug fix below (extra edges, no new states).
- **Repaired an absorbing-state defect** found during the sweep:
  `BlockOnDenial` was enabled only from `RUNNING`, so a machine denied
  again *after* a retry was trapped in `BLOCKED/DENIED`. The guard now
  admits `RUNNING` and `BLOCKED`; the trap is gone and the model is
  deadlock-free under `CHECK_DEADLOCK TRUE` across the whole sweep.
- **Saturating task counter** (`MaxTasks`) replaces the unbounded
  increment, so liveness configs need no (unsound) state constraint.
- **Added gating constants** `EnableFaults` (MachineMode) and
  `EnableTimeouts` (ReservationState); the baseline configs set them to
  TRUE and reproduce the prior results bit-for-bit (38/14 and 93/35).
- **Removed the previous `CAPCoordination.cfg`**: it combined
  `PROPERTIES NoStarvation` with `CHECK_DEADLOCK TRUE` and *no* state
  constraint, so `TypeOK` was violated once a machine's `taskCount`
  exceeded its bound (the counter was unbounded). It never ran in CI
  (only `CAPCoordination_safety.cfg` did) and is superseded by the
  liveness configs above.
