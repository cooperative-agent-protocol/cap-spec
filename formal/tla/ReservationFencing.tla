--------------------------- MODULE ReservationFencing ---------------------------
(* TLA+ component model: reservation safety under ADVERSARIAL delivery, and the
 * fencing-token mechanism that restores single-holder actuation.
 *
 * The composite CAPCoordination model assumes reliable, ordered delivery: a
 * grant couples the holder map instantly and a release is never lost. Real CAP
 * runs over gRPC/MQTT where a ReservationStatus (grant/expiry/release) can be
 * delayed, dropped, or replayed -- exactly the regime the fault-injection
 * campaign attacks empirically ("dropping a ReservationStatus causes
 * exclusivity violations without arbitration"). This module models that
 * adversary and shows a monotonic per-resource grant epoch (a Chubby/ZooKeeper
 * fencing token) makes the exclusivity invariant hold again.
 *
 *   Fenced = FALSE : a stale holder whose expiry/release notification was lost
 *                    still acts on the resource. After the arbiter re-grants it,
 *                    TWO machines actuate the same load point -- ExclusiveActuation
 *                    is VIOLATED. This reproduces, as a model-checked
 *                    counterexample, the fault campaign's lost-status finding.
 *   Fenced = TRUE  : every grant carries a monotonically increasing epoch; a
 *                    holder may act only while its token equals the resource's
 *                    current epoch, so a stale holder (older token) cannot act.
 *                    ExclusiveActuation HOLDS.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Machines,       \* e.g., {"m1", "m2"}
    Resources,      \* e.g., {"LP-1"}
    MaxEpoch,       \* epoch counter saturation bound (finiteness)
    Fenced          \* BOOLEAN: TRUE = enforce the fencing token on actuation

NONE == "NONE"

VARIABLES
    arbHolder,      \* arbHolder[r] in Machines \cup {NONE}: arbiter's authoritative holder
    arbEpoch,       \* arbEpoch[r] in 0..MaxEpoch: monotonic grant-generation counter
    believes,       \* believes[m] in Resources \cup {NONE}: resource m believes it holds
    token           \* token[m] in 0..MaxEpoch: the fencing token m was granted

vars == <<arbHolder, arbEpoch, believes, token>>

TypeOK ==
    /\ arbHolder \in [Resources -> Machines \cup {NONE}]
    /\ arbEpoch  \in [Resources -> 0..MaxEpoch]
    /\ believes  \in [Machines -> Resources \cup {NONE}]
    /\ token     \in [Machines -> 0..MaxEpoch]

Init ==
    /\ arbHolder = [r \in Resources |-> NONE]
    /\ arbEpoch  = [r \in Resources |-> 0]
    /\ believes  = [m \in Machines |-> NONE]
    /\ token     = [m \in Machines |-> 0]

\* ─── Actuation predicate ─────────────────────────────────────────────
\* A machine "acts as holder" of r if it believes it holds r and -- when
\* fencing is on -- its token matches the resource's current grant epoch.
ActsAsHolder(m, r) ==
    /\ believes[m] = r
    /\ (~Fenced \/ token[m] = arbEpoch[r])

\* ─── Safety: exclusive actuation ─────────────────────────────────────
\* At most one machine simultaneously acts on a given resource as its holder.
ExclusiveActuation ==
    \A r \in Resources :
        Cardinality({ m \in Machines : ActsAsHolder(m, r) }) <= 1

\* ─── Transitions ─────────────────────────────────────────────────────

\* Arbiter grants a free resource r to m: bump the epoch (monotonic),
\* record the authoritative holder, and deliver the matching fencing token.
Grant(m, r) ==
    /\ arbHolder[r] = NONE
    /\ believes[m] = NONE
    /\ arbEpoch[r] < MaxEpoch
    /\ arbEpoch'  = [arbEpoch  EXCEPT ![r] = @ + 1]
    /\ arbHolder' = [arbHolder EXCEPT ![r] = m]
    /\ believes'  = [believes  EXCEPT ![m] = r]
    /\ token'     = [token     EXCEPT ![m] = arbEpoch[r] + 1]

\* Clean release: the holder releases r and the arbiter is notified.
Release(m, r) ==
    /\ arbHolder[r] = m
    /\ believes[m] = r
    /\ arbHolder' = [arbHolder EXCEPT ![r] = NONE]
    /\ believes'  = [believes  EXCEPT ![m] = NONE]
    /\ UNCHANGED <<arbEpoch, token>>

\* ADVERSARIAL: the arbiter reclaims r (grant window elapsed / preemption) but
\* the expiry/release notification to the holder is LOST -- the holder keeps
\* believing it holds r. This is the dropped-ReservationStatus fault.
ExpireLostNotify(r) ==
    /\ arbHolder[r] /= NONE
    /\ arbHolder' = [arbHolder EXCEPT ![r] = NONE]
    /\ UNCHANGED <<arbEpoch, believes, token>>

\* Recovery: a machine that believes it holds r but is no longer the arbiter's
\* holder eventually reconciles (e.g., via a heartbeat) and drops the stale
\* belief. Bounds the state space and models recovery.
ClearStaleBelief(m) ==
    /\ believes[m] /= NONE
    /\ arbHolder[believes[m]] /= m
    /\ believes' = [believes EXCEPT ![m] = NONE]
    /\ UNCHANGED <<arbHolder, arbEpoch, token>>

Next ==
    \/ \E m \in Machines, r \in Resources : Grant(m, r)
    \/ \E m \in Machines, r \in Resources : Release(m, r)
    \/ \E r \in Resources : ExpireLostNotify(r)
    \/ \E m \in Machines : ClearStaleBelief(m)

Spec == Init /\ [][Next]_vars

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => []ExclusiveActuation   \* holds iff Fenced = TRUE

================================================================================
