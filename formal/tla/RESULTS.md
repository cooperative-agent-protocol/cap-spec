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

### ReservationRecovery (arbiter crash/restart + partition)

Extends the fencing model with arbiter **crash + restart** (the arbiter loses its
volatile holder map; machines keep their pre-crash belief and token) and reuses
`ExpireLostNotify` as the **partition** case (the arbiter reclaims after a lease
timeout while a partitioned holder keeps believing). Fencing is always on; the free
variable `PersistEpoch` selects whether the monotonic grant epoch survives the restart
on stable storage. This keeps the honest scope: arbiter **availability** across failure
is *not* modelled (a replicated/consensus arbiter is future work); the question decided
here is whether recovery can ever cause a double-actuation.

| Config | PersistEpoch | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `ReservationRecovery_persisted.cfg` | TRUE | TypeOK, ExclusiveActuation | **holds** | 209 / 97 |
| `ReservationRecovery_volatile.cfg` | FALSE | ExclusiveActuation | **violated** | counterexample (174 dist) |

A persisted epoch fences every pre-crash holder after restart (a re-grant carries an
epoch above every pre-crash token), so exclusivity holds; a volatile epoch that resets
to 0 lets a re-grant re-issue an epoch that collides with a stale token, so two machines
actuate the same resource. The model-checked recovery requirement is therefore: persist
the grant epoch monotonically across restart.

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
| `MultiResource_unordered.cfg` | FALSE | (same) | **deadlock** | 15 / 9 (3-state circular-wait CEX) |

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

### ByzantineReservation (untrusted agents, trusted arbiter)

Every other model assumes agents follow the protocol. CAP's architecture
assumes the opposite — machine agents and their LLMs are untrusted, and the
Site Agent's arbiter (and the Safety Supervisor) are the trusted enforcement
points. This component lets a machine **lie** (assert it holds a resource it
was never granted) and checks whether exclusive actuation survives.
`TrustedArbiter` selects whether actuation is gated by the arbiter's
authoritative holder map or by the machine's self-asserted claim.

| Config | TrustedArbiter | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `ByzantineReservation_trusted.cfg` | TRUE | TypeOK, ArbiterExclusive, NoTwoActuators | **holds** | 21 / 8 |
| `ByzantineReservation_untrusted.cfg` | FALSE | NoTwoActuators | **violated** | 3-state counterexample |

**Finding (exclusivity is an invariant of the arbiter, not of agent honesty).**
With `TrustedArbiter = TRUE`, a machine actuates a resource only if the
arbiter's authoritative map recognises it as the holder, so a false self-claim
carries no authority and `NoTwoActuators` **holds**. With
`TrustedArbiter = FALSE` it is **violated**:
```
Grant(m1, LP-1)          ; arbiter grants LP-1 to m1 (m1 actuates)
ByzantineClaim(m2, LP-1) ; m2 lies — asserts LP-1 without a grant
→ both m1 (true grantee) and m2 (liar) actuate LP-1.
```
`ArbiterExclusive` (the arbiter's own map is single-holder) holds in both
regimes — the lie corrupts actuation only when the design trusts the agent's
self-report. This is the verified form of CAP's central trust model: the
protocol's safety does not depend on machine agents (or the LLMs driving them)
behaving correctly.

### TimedHandover (bounded-time resolution)

The untimed models show a handover is *eventually* resolved; for a
safety-relevant protocol, "eventually safe-stops" is not a safety property ---
"safe-stops within a bounded time" is. This component adds a discrete clock and
verifies a bounded-response property: from a request, the handover resolves
(Completed, or TimedOut → SafeStop) within `Deadline` ticks. `Enforced` toggles
whether the deadline is guaranteed to fire.

| Config | Enforced | Property | Verdict | States (gen/dist) |
|---|---|---|---|---|
| `TimedHandover_enforced.cfg` | TRUE (Deadline=3) | TypeOK, BoundedResolution | **holds** | 31 / 18 |
| `TimedHandover_unenforced.cfg` | FALSE (Deadline=3) | BoundedResolution | **violated** | clock ages past the deadline |

**Finding (bounded time, not just eventually).** With the deadline enforced --- a
pending handover cannot let time pass once `clock = Deadline` without resolving
or timing out --- `BoundedResolution` (a pending handover never ages past
`Deadline`) **holds**. Without that guarantee, time advances while the handover
stays `REQUESTED`, the clock climbs past `Deadline`, and the invariant is
**violated**. This upgrades the untimed `HandoverEventuallyResolved` to a
bounded-time guarantee, the form a real-time safety argument needs.

### ReservationInductive (Apalache inductive invariant — unbounded by induction)

The composite safety sweep is explicit-state model checking up to a bounded
instance (N <= 5). This result establishes the core exclusivity invariant the
stronger way --- as an **inductive invariant**, checked by **Apalache 0.58.0**
(symbolic / SMT) over symbolic machine and resource sets (`Gen(4)`). An
inductive invariant holds in every reachable state by induction (preserved by
every step from any state that satisfies it), rather than being merely free of a
counterexample within an explored depth/instance.

`Disjoint` (NoDoubleGrant): no resource is held by two machines.

| Check | apalache-mc invocation | Verdict |
|---|---|---|
| base: `Init => IndInv` | `check --cinit=ConstInit --init=Init --inv=IndInv --length=0` | **OK** |
| step: `IndInv /\ Next => IndInv'` | `check --cinit=ConstInit --init=IndInv --inv=IndInv --length=1` | **OK** |
| non-vacuity sanity: a non-inductive predicate's step | `check --init=NotInductive --inv=NotInductive --length=1` | **violation found** (as expected) |

`IndInv == TypeOK /\ Disjoint`. The base and inductive step both pass, so
`Disjoint` holds in all reachable states; the deliberately non-inductive
`NotInductive` ("nobody ever holds anything") fails its inductive step,
confirming the SMT check discriminates (the positive result is not vacuous).
This complements the TLC sweep with a proof-by-induction of exclusivity that
does not depend on enumerating a fixed fleet size. (Apalache is a separate
toolchain from the TLC `run_sweep.sh`; the three invocations above reproduce it.)

**Fencing, inductively (`FencingInductive`).** The fencing property is also
proved as an inductive invariant: with a monotonic per-resource grant epoch, at
most one machine *actuates* a resource (believes it holds it AND its token
equals the resource's current epoch), even when a holder's release/expiry notice
is lost. `IndInv == TypeOK /\ Singletons /\ EpochDominates /\
ExclusiveActuation`; the base (`--init=Init --inv=IndInv --length=0`) and
inductive step (`--init=IndInv --inv=IndInv --length=1`) both discharge under
Apalache over symbolic sets, so a stale (older-token) holder can never
co-actuate with the current grantee, for any fleet size. `Singletons` and
`EpochDominates` are the supporting invariants that make `ExclusiveActuation`
inductive.

**Handover ownership, inductively (`HandoverInductive`).** The handover
receiver-ownership property (P4) is likewise proved as an inductive invariant
for the **atomic** ownership-transfer discipline: throughout a handover's
`IN_PROGRESS` window the handover-point resource is held by the receiver, never
momentarily unheld. The atomic transfer (sender release + receiver grant in one
step) together with plain acquire/release being disabled while a handover on the
resource is active is what makes ownership inductive; `IndInv == TypeOK /\
Singletons /\ NoDoubleGrant /\ ReceiverOwnership`, and the base
(`check --cinit=ConstInit --init=Init --inv=IndInv --length=0`) and inductive
step (`check --cinit=ConstInit --init=IndInv --inv=IndInv --length=1`) both
discharge (EXITCODE OK) under Apalache over symbolic machine/resource sets, with
the non-inductive sanity predicate `NotInductive` ("no handover is ever
IN_PROGRESS") failing its step as expected (EXITCODE ERROR 12). The naive
release-then-reacquire discipline, which the TLC sweep shows VIOLATES P4, is
correctly NOT inductive and is excluded from this model.

**Deadlock-freedom, inductively (`MultiResourceInductive`).** Deadlock-freedom
is a *progress* property (the explicit-state `MultiResource` result checks it via
TLC `CHECK_DEADLOCK`); its unbounded part is the underlying STATE invariant that
powers the classic ordered-acquisition argument. `OrderedPrefix`: every machine
holds a downward-closed prefix of the resource order, so it only ever waits for a
resource LARGER than everything it holds --- a wait-for cycle would force
`r1 < r2 < ... < r1`, a contradiction, hence no circular wait. `IndInv ==
TypeOK /\ NoDoubleOwner /\ OrderedPrefix`; base
(`check --cinit=ConstInit --init=Init --inv=IndInv --length=0`) and inductive step
(`check --cinit=ConstInit --init=IndInv --inv=IndInv --length=1`) both discharge
(EXITCODE OK) under Apalache over symbolic machine/resource sets, with the
non-vacuity sanity predicate failing its step (EXITCODE ERROR 12). So the
no-circular-wait condition that yields deadlock-freedom holds for any number of
machines and resources.

Four of the core structural invariants --- no-double-grant, fencing exclusivity,
handover receiver-ownership, and the acquisition-order (no-circular-wait)
invariant --- are thus established by induction, independent of fleet size,
complementing the bounded TLC sweep. A full machine-checked refinement proof
(TLAPS) linking the specifications to the implementation remains future work.

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

- **Added `ReservationInductive`** (Apalache 0.58.0): NoDoubleGrant verified as
  an inductive invariant (base + inductive step both OK) over symbolic
  machine/resource sets, with a non-vacuity sanity check (a non-inductive
  predicate's step fails). Complements the bounded TLC sweep with a
  proof-by-induction that does not enumerate a fixed fleet size.
- **Added `TimedHandover`**, a discrete-time bounded-response model: with the
  deadline enforced a pending handover resolves within `Deadline` ticks
  (BoundedResolution holds); without it the clock ages past the deadline
  (violated). Upgrades the untimed eventual-resolution result to a bounded-time
  guarantee.
- **Added `ByzantineReservation`**, modelling a lying machine: exclusive
  actuation holds under a trusted arbiter and is violated when the design
  honours a machine's self-asserted hold. Verifies that CAP's exclusivity is
  an invariant of the arbiter, not of agent honesty (the architecture's
  untrusted-agent premise).
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

## Refinement from CAPCoordination to the inductive models, and the cutoff (2026-11, reviewer R2-1)

The inductive results (`ReservationInductive`, `HandoverInductive`) are proved on structurally simplified models.
`CAPCoordinationRefinement.tla` maps CAPCoordination onto them and TLC checks the refinement (every CAPCoordination
step maps to an abstract step or a stutter): `held`/`granted` <- the GRANTED reservations, `requested` <- the
REQUESTED ones, `hoState` as is, `receiverOf` <- `hoReceiver`. The abstractions as they were did NOT preserve two
transitions, and the check finds each:

| Configuration | Abstraction | Verdict |
|---|---|---|
| `refinement_ho_N3R1_atomic_without.cfg` | original (no Transfer, no Deny) | **violated at `BeginHandoverAtomic`** (an atomic hand-over is neither an Acquire nor a Release) |
| `refinement_N3R2_without_deny.cfg` | original Deny-less handover model | **violated at `DenyResource`** |
| `refinement_ho_N2R1_atomic.cfg` | extended (`Transfer`, `Deny`) | refinement holds (204 states) |
| `refinement_ho_N3R1_atomic.cfg` | extended | refinement holds (3,088 states) |
| `refinement_N3R2.cfg` | extended | refinement holds (119,601 states) |

`ReservationInductive` gained `Transfer` and `HandoverInductive` gained `Deny`; both stay inductive (Apalache 0.58.0,
`check --cinit=ConstInit --init=Init --inv=IndInv --length=0` and `--init=IndInv --length=1`: EXITCODE OK).

**Cutoff.** Each invariant is a conjunction of per-resource and pairwise conditions, every action involves at most
three machines and one resource, and every guard quantifies universally over machines, so it survives projection.
A counterexample to inductiveness at any fleet size therefore projects onto one with at most 7 machines and 2
resources for `HandoverInductive`, and 4 machines and 2 resources for `ReservationInductive`.
`HandoverInductive` checked with `ConstInitCutoff` (`Gen(7)` machines, `Gen(2)` resources): base OK, step OK,
`NotInductive` step violated (as it must). `ReservationInductive`'s `Gen(4)` already covers its cutoff. Together
with the refinement above, NoDoubleGrant and receiver ownership hold for CAPCoordination's reservation and
hand-over transitions at any number of machines. The CAPCoordination model itself was checked at the swept sizes.

## PermitTiming: the lease lemma for entry permits (2026-11)

`PermitTiming.tla` models one permit with drifting monotonic clocks (each advances K-D..K+D per tick of K real units,
rho = D/K) and delayed messages. K=10, D=1 (rho = 0.1), T=40, Delta=10, 8 ticks.

| Config | Rule | Contained (usable => counted) | CrossingCovered |
|---|---|---|---|
| `PermitTiming_send.cfg` | machine times from the request's SEND for T(1-rho); arbiter counts T(1+rho) from the grant | **holds** (2,467,981 states) | **holds** |
| `PermitTiming_receive.cfg` | machine times from the grant's receipt | **violated** | -- |
| `PermitTiming_nodrift.cfg` | both use T without the rho factors | **violated** | -- |

The bounded check is a sanity check of the algebraic proof in the paper's appendix (which holds for any T, rho < 1 and
any delays); it also confirms the two broken rules are distinguishable.

## ZoneTable: how a gate comes to know a zone (2026-11)

`OccupancyHandover` takes for granted that every gate knows the zone. `ZoneTable.tla` models how it comes to: the
arbiter's versioned table of zones, sent over ordered streams; the machines' heartbeats that report the table each
gate enforces; restarts of a machine (an empty gate, a new stream) and of the arbiter (with its journal: the zones
taken up again; without it: an empty table). Two machines, two starts of the arbiter, two versions per start, two
geometries of the zone, two messages per stream.

| Config | Rule | Safe (while a machine is authorised, no other gate lets its machine in unchecked) |
|---|---|---|
| `ZoneTable_ack.cfg` | a gate without a table lets nothing move; no authorisation before every other gate has reported a table of this start with the zone as it stands; no table sent after a restart without the journal until the earlier start's authorisations have lapsed | **holds** (50,712,315 states, depth 44) |
| `ZoneTable_noack.cfg` | authorise without waiting for the reports | **violated** (7 steps) |
| `ZoneTable_failopen.cfg` | a gate without a table lets its machine move | **violated** (9 steps) |
| `ZoneTable_nohold.cfg` | a restarted arbiter sends its still empty table at once | **violated** (11 steps) |
| `ZoneTable_ack_reach.cfg` | (reachability) an authorisation is reachable under the protocol's rule | `NeverAuthorised` **violated**, as it must be |

The rule came from a defect of the reference implementation that a trial on a second site layout exposed (a gate
learned the zones only from its machine's work orders). The first version of the repair kept a zone across a restart
of the arbiter on the gate's side; the model found the execution it missed (a machine restarts, then the arbiter
restarts and sends its empty table, which opens the machine's gate while an authorisation of the earlier start is
still usable), and the rule above replaced it. Assumed: a zone is not moved while an authorisation for it is out; a
stream delivers in order; no machine the zone is closed to is inside it when it is registered.

## OccupancyHandover with three carriers (2026-11)

The schemes that satisfy S1-S3 with two carriers, checked again with three (`family/gen_m3_cfgs.py`: the carriers
are model values and the configurations use `SYMMETRY Symm`; three grant generations, one arbiter restart; S1-S3,
and G1-G2 for the schemes with designated succession). The twelve schemes with the journal kept and the eight that
stay safe with it lost: 20 of 20 configurations hold. Raw verdicts:
`family/results/m3_verdicts_before_site_release.txt` (before `SiteRelease`; superseded below).

| Scheme | Journal | TLC | Distinct states |
|---|---|---|---|
| deny-local-onVacate-none-designated | kept | no error | 228,148 |
| MutexGroup | kept | no error | 308,286 |
| deny-permit-onVacate-none-designated | kept | no error | 5,431,544 |
| deny-permit-onVacate-none-free | kept | no error | 9,439,772 |
| deny-permit-onVacate-ttlVacate-designated | kept | no error | 23,180,264 |
| LeaseFencedVacate | kept | no error | 47,385,690 |
| queue-local-onVacate-none-designated | kept | no error | 339,110 |
| queue-local-onVacate-none-free | kept | no error | 231,690 |
| queue-permit-onVacate-none-designated | kept | no error | 6,681,268 |
| queue-permit-onVacate-none-free | kept | no error | 5,644,280 |
| CAP | kept | no error | 30,741,428 |
| queue-permit-onVacate-ttlVacate-free | kept | no error | 30,843,358 |
| deny-permit-onVacate-none-designated | lost | no error | 13,987,348 |
| deny-permit-onVacate-none-free | lost | no error | 24,346,612 |
| deny-permit-onVacate-ttlVacate-designated | lost | no error | 142,816,586 |
| LeaseFencedVacate | lost | no error | 223,746,654 |
| queue-permit-onVacate-none-designated | lost | no error | 19,346,688 |
| queue-permit-onVacate-none-free | lost | no error | 16,386,946 |
| CAP | lost | no error | 212,304,563 |
| queue-permit-onVacate-ttlVacate-free | lost | no error | 151,463,364 |

## OccupancyHandover with Site-side releases and the custody rule (2026-11-12)

An attempt to prove S1-S3 for any number of machines found that the model had every release made by the holder's
own agent, which voids its permit in the same step. In the reference implementation the Site's coordinator holds the
reservations and gives a zone up for its holder (a load no longer wanted, a hand-over it routes); the holder's gate
hears of it only by a notice, which a cut link withholds. A holder given up while it held an unused permit left
custody as soon as it was seen outside and could still enter on the permit, unaccounted for. Two constants were
added: `SiteRelease` (the action `SiteRel(m)`: the Site gives the zone up for its holder at any time) and
`CustodyUntilLapse` (the custody rule: a machine leaves custody only when it is seen outside AND no permit issued
to it is still counted). Both are TRUE in every setting below unless named.

### The family of 90 (two carriers)

| Setting | Schemes that satisfy S1-S3 |
|---|---|
| Site-side releases, journal kept (`base`) | 8 |
| Site-side releases, journal lost (`lossy`) | 8 (the same) |
| holder's own releases only, journal kept (`ownRelease`) | 12 |
| holder's own releases only, journal lost (`ownRelease_lossy`) | 8 |

With Site-side releases every safe scheme has an arbiter, a gate with time-limited permits (`Gate = "permit"`),
release on vacancy, and expiry none or into custody. The four schemes that are safe only with the holder's own
releases have a gate that remembers grants (`Gate = "local"`): MutexGroup, deny-local-onVacate-none-designated, queue-local-onVacate-none-designated, queue-local-onVacate-none-free.
Given up by the Site while outside, such a holder enters on the grant it remembers after the next machine was
admitted (MutexGroup: S3 in 6 steps, S1 in 10).

### The eight safe schemes: guarantees, ablations, and the proof's invariant

| Scheme | G1, G2 | G4 | no custody rule | no A2 | no A4 (journal kept) | no A4 (lost) | no grace wait | no A5 | no boot id | AbsInv kept / lost / lost, no A5 |
|---|---|---|---|---|---|---|---|---|---|---|
| deny-permit-onVacate-none-designated | holds | **violated** (G4) | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| deny-permit-onVacate-none-free | **violated** (G1,G2) | **violated** (G4) | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| deny-permit-onVacate-ttlVacate-designated | holds | holds | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| LeaseFencedVacate | **violated** (G1,G2) | holds | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| queue-permit-onVacate-none-designated | holds | **violated** (G4) | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| queue-permit-onVacate-none-free | **violated** (G1) | **violated** (G4) | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| CAP | holds | holds | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |
| queue-permit-onVacate-ttlVacate-free | **violated** (G1) | holds | **violated** (S1,S2) | **violated** (S1,S2) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | **violated** (S1,S2,S3) | holds | holds | holds / holds / holds |

Without authentication (A5) all eight remain safe, and the four with designated succession keep G1 and G2: a
request, release or hand-over in another machine's name does what `SiteRel` may do anyway, and the custody rule
keeps the machine accounted for until it can no longer enter. What safety rests on instead is that a permit reaches
only the machine it was issued to. Without sound timing (A4) none remains safe, even with the journal kept: custody
ends when the arbiter stops counting a machine's permits, which is safe only if the machine has stopped using them
by then. With the holder's own releases only (`--setting ownRelease_noA4d`, journal kept), the eight schemes that
never expire a holder keep S1 and S2 without A4; the four with timed permits lose S3 (a permit the arbiter has
stopped counting is still usable: five or six steps), and the four that admit on a remembered grant keep S3 as well
(`family/results/ownRelease_noA4d_safe12.json`). An earlier note that said these schemes "do not need A4" used an
older definition of S3 and was removed. Without authentication and with restarts that lose the journal
(`--setting noA5_lossy`), all eight safe schemes keep S1-S3 and the four with designated succession G1 and G2
(`family/results/noA5_lossy_safe8.json`, up to 28,718,676 states).
With Site-side releases, schemes that differ only in expiry (none, or into custody) have the same state space here:
`SiteRel` may take any holder's zone at any time, which subsumes `LeaseExpire`. `AbsInv` is
the invariant of the unbounded proof below, in this model's variables; it holds for all eight in all three settings.
Result files: `family/results/{base,lossy,ownRelease,ownRelease_lossy,trivial}.json`, `family/results/*_safe8.json`.

### S1-S3 for any number of machines, zones and permits (`../smt/occupancy_inductive.py`)

An abstraction of the schemes with an arbiter, a permit gate and custody, over uninterpreted sorts of machines,
zones and permit identifiers, with any symmetric irreflexive incompatibility relation per zone. Its fifteen
actions (Hold, Issue, Transfer, Release, Vacate, ArbLapse, RealLapse, Receive, Lose, Forget, Enter, Exit, Restart,
GraceOver, AllVacant) do not look at who asked, so releases and hand-overs in any machine's name, by any client or by
the Site, are steps of it. An invariant of ten conjuncts (S1, S2, S3 among them) is inductive: each of the
15 x 10 = 150 implications is a formula of the Bernays-Schoenfinkel class, and Z3 (4.15.0) reports each negation
unsat (about 12 s in all). Removing the custody rule, the vacancy sensing, either condition of a permit, either half
of the timing lemma, the grace wait or the gate makes the invariant non-inductive. Two checks turned out to be
implied: that no permit of an incompatible machine is counted when a permit is issued or a zone is granted, and
that no incompatible machine is in custody when a zone is granted. Run: `python3 formal/smt/occupancy_inductive.py`.

The three-carrier checks of the section above were made before `SiteRelease`; they are superseded by the next
section, and their verdicts are kept in `family/results/m3_verdicts_before_site_release.txt`.

## OccupancyHandover with three carriers, Site-side releases and the custody rule (2026-11-12)

The eight schemes that satisfy S1-S3 with two carriers when the Site may give a zone up (above), checked again with
three carriers (`family/gen_m3_cfgs.py`: carriers as model values, `SYMMETRY Symm`; three grant generations, one
arbiter restart; S1-S3, G1-G2 for the schemes with designated succession, and the unbounded proof's invariant
`AbsInv`). Raw verdicts: `family/results/m3_verdicts.txt`. All sixteen hold; the configurations with a lost journal
are the large ones (up to 448 M distinct states).

| Scheme | Journal | TLC | Distinct states | Seconds |
|---|---|---|---|---|
| deny-permit-onVacate-none-designated | kept | no error | 43169540 | 289 |
| deny-permit-onVacate-none-free | kept | no error | 91635516 | 618 |
| deny-permit-onVacate-ttlVacate-designated | kept | no error | 43169540 | 289 |
| LeaseFencedVacate | kept | no error | 91635516 | 619 |
| queue-permit-onVacate-none-designated | kept | no error | 58939496 | 394 |
| queue-permit-onVacate-none-free | kept | no error | 60211196 | 405 |
| CAP | kept | no error | 58939496 | 394 |
| queue-permit-onVacate-ttlVacate-free | kept | no error | 60211196 | 404 |
| deny-permit-onVacate-none-designated | lost | no error | 272351648 | 2044 |
| deny-permit-onVacate-none-free | lost | no error | 448143548 | 3433 |
| deny-permit-onVacate-ttlVacate-designated | lost | no error | 272351648 | 1994 |
| LeaseFencedVacate | lost | no error | 448143548 | 3488 |
| queue-permit-onVacate-none-designated | lost | no error | 416224770 | 3177 |
| queue-permit-onVacate-none-free | lost | no error | 312290502 | 2326 |
| CAP | lost | no error | 416224770 | 3214 |
| queue-permit-onVacate-ttlVacate-free | lost | no error | 312290502 | 2383 |

## The tables of the paper, and the family on an implementation (2026-11-12)

`family/make_tables.py` writes the LaTeX tables and number macros of the paper's verification section from the result
files of this directory (`--m3 family/results/m3_verdicts.txt` adds the three-carrier checks); nothing in that section
is typed by hand. The public `cap-coordination-kit` runs the same family of 90 schemes on an arbiter's code
(`python -m cap_coordination_kit.family_fuzz`): randomised executions with an untrusted client, delayed and lost
messages, drifting clocks and restarts, S1-S3 checked after every step. The schemes in which it finds no violation are
those this directory finds safe, in each of the four settings (Site-side or own releases, journal kept or lost: 8, 8,
12, 8), and removing the custody rule's second half, the bound on clock drift or sound vacancy sensing breaks all
eight safe schemes. A randomised test finds violations; it does not show that there are none.


Correspondence of the abstraction's actions to the steps of `OccupancyHandover` (argued by hand; the invariant
`AbsInv` is also checked on the model itself at two and three machines):

| Action | May occur when | Covers in the occupancy model |
|---|---|---|
| Hold | the guard is open and the zone has no holder | the grant of a free zone |
| Issue | the guard is open, the machine holds the zone, and no machine incompatible with it is in the zone's custody | the permit sent with a grant, a further permit for the holder |
| Transfer | the sender holds the zone; the sender enters custody | a hand-over, by request, by a routed release or on expiry |
| Release | the machine holds the zone; it enters custody | a release by the machine's client, by another client or by the Site; an expiry |
| Vacate | the machine is in custody, is outside the zone, and no permit of its own for the zone is counted | a confirmed vacancy |
| ArbLapse | a counted permit is no longer valid | the arbiter's timer |
| RealLapse | a valid permit is not usable by its machine | the end of a permit's validity |
| Receive | a permit is in flight; it becomes usable if it is still valid | a permit's arrival |
| Lose, Forget | always | a lost or voided message; a gate's timer, a restart of the machine, a release by its own agent |
| Enter | the machine is outside and has a usable permit, which is used up | an entry through the gate |
| Exit | the machine is inside | an exit, a removal by an operator |
| Restart | always; holder, custody and counted permits are forgotten | a restart without the journal, or one that finds a journal written while the zones were closed |
| GraceOver | the guard waits for permits and none is valid | the end of the grace period |
| AllVacant | the guard waits for vacancy and no machine is inside any zone | the reopening of the zones |

A restart that keeps the journal while the zones are open restores the state, the guard included, and is no step of
the abstraction.

## Two restarts, each keeping or losing the journal (2026-11-13)

`Restart = "mixed"` lets each restart of the arbiter keep the journal or lose it, with `MaxBoot = 2`. The journal
keeps the restart guard: a restart that finds a journal written while the zones were closed (during the wait after a
restart that lost the journal) closes them again and starts both waits afresh. `Restart = "mixedOld"` is the rule
before this date, under which a restart that found a journal opened the zones whatever it said.

With the earlier rule the protocol and the lease with a vacancy check violate S1-S3 (LeaseFencedVacate: S1 in 14 steps; CAP: S1 in 14 steps, without machine faults
and with two grant generations; LeaseFencedVacate: S1 in 14 steps; CAP: S1 in 13 steps, with faults and three generations): the holder enters, the arbiter restarts
without its journal and, during the wait, restarts again and finds the journal written meanwhile, which holds no
holder; the zones open and the next machine enters onto the first. The model checks with one restart, the SMT
abstraction (which treats a journalled restart as a stutter) and the kit's family_fuzz (which kept or lost the
journal for a whole run) could not see it; an independent review of the proofs found it. Results:
`family/results/mixedOld_named2.json`, `family/results/mixedOldSmall_named2.json`, traces in
`family/results/traces/mixedOldSmall/`.

With the rule as now written, the eight schemes that are safe with one restart stay safe over two restarts of either
kind (`family/results/mixedSmall_safe8.json`; two machines, no machine faults, two grant generations, `run_family.py
--setting mixedSmall`):

| Scheme | Holds | Violated | Distinct states |
|---|---|---|---|
| deny-permit-onVacate-none-designated | G1, G2, S1, S2, S3 | - | 4,237,912 |
| deny-permit-onVacate-none-free | S1, S2, S3 | G1, G2 | 7,050,146 |
| deny-permit-onVacate-ttlVacate-designated | G1, G2, S1, S2, S3 | - | 4,237,912 |
| LeaseFencedVacate | S1, S2, S3 | G1, G2 | 7,050,146 |
| queue-permit-onVacate-none-designated | G1, G2, S1, S2, S3 | - | 4,551,321 |
| queue-permit-onVacate-none-free | G2, S1, S2, S3 | G1 | 4,617,021 |
| CAP | G1, G2, S1, S2, S3 | - | 4,551,321 |
| queue-permit-onVacate-ttlVacate-free | G2, S1, S2, S3 | G1 | 4,617,021 |

The same check with machine faults and three grant generations (`--setting mixed`) is far larger and is reported in
`family/results/mixed_*.json` when it has finished.
