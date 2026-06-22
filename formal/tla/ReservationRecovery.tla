--------------------------- MODULE ReservationRecovery ---------------------------
(* TLA+ component model: single-arbiter SAFETY across arbiter crash/restart and
 * network partition, given the monotonic grant-epoch fencing token.
 *
 * CAPCoordination and ReservationFencing both assume the arbiter never fails.
 * A reviewer asks the natural availability question: the coordinator that holds
 * the authoritative reservation is a single point of failure. This module keeps
 * that honest scope -- a replicated arbiter (Raft/Paxos consensus over the holder
 * map) is future work and AVAILABILITY across arbiter failure is NOT modelled --
 * but shows the SAFETY question is separable and decidable: a crash/restart or a
 * partition must never let two machines actuate the same load point.
 *
 * Fencing is always ON here (we are past the ReservationFencing result that
 * fencing is necessary). The free variable is PersistEpoch:
 *
 *   PersistEpoch = TRUE  : on restart the arbiter recovers its per-resource grant
 *                          epoch from stable storage (a durable monotonic counter,
 *                          as Chubby/ZooKeeper persist their epoch). Any post-crash
 *                          re-grant therefore carries an epoch strictly above every
 *                          token issued before the crash, so a pre-crash holder is
 *                          fenced. ExclusiveActuation HOLDS.
 *   PersistEpoch = FALSE : the epoch is volatile and resets to 0 on restart. A
 *                          re-grant can then re-issue an epoch that COLLIDES with a
 *                          stale pre-crash token, so a crashed-through holder and a
 *                          fresh holder both validate -- ExclusiveActuation is
 *                          VIOLATED. This is the model-checked reason the recovery
 *                          requirement is "persist the epoch", not merely "fence".
 *
 * Partition is the existing ExpireLostNotify action (the arbiter reclaims after a
 * lease timeout while the partitioned holder keeps believing it holds); the same
 * fencing token that defeats a lost release defeats a partitioned stale holder.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Machines,       \* e.g., {"m1", "m2"}
    Resources,      \* e.g., {"LP-1"}
    MaxEpoch,       \* epoch counter saturation bound (finiteness)
    PersistEpoch    \* BOOLEAN: TRUE = epoch survives restart on stable storage

NONE == "NONE"

VARIABLES
    arbHolder,      \* arbHolder[r] in Machines \cup {NONE}: arbiter's authoritative holder (VOLATILE)
    arbEpoch,       \* arbEpoch[r] in 0..MaxEpoch: monotonic grant-generation counter (durable iff PersistEpoch)
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

\* Fencing is always enforced here: a machine acts as holder only while its token
\* matches the resource's current grant epoch.
ActsAsHolder(m, r) ==
    /\ believes[m] = r
    /\ token[m] = arbEpoch[r]

\* Safety: at most one machine actuates a given resource as its holder.
ExclusiveActuation ==
    \A r \in Resources :
        Cardinality({ m \in Machines : ActsAsHolder(m, r) }) <= 1

\* ─── Transitions ─────────────────────────────────────────────────────

\* Arbiter grants a free resource: bump the epoch (monotonic), record the holder,
\* deliver the matching fencing token.
Grant(m, r) ==
    /\ arbHolder[r] = NONE
    /\ believes[m] = NONE
    /\ arbEpoch[r] < MaxEpoch
    /\ arbEpoch'  = [arbEpoch  EXCEPT ![r] = @ + 1]
    /\ arbHolder' = [arbHolder EXCEPT ![r] = m]
    /\ believes'  = [believes  EXCEPT ![m] = r]
    /\ token'     = [token     EXCEPT ![m] = arbEpoch[r] + 1]

\* Clean release.
Release(m, r) ==
    /\ arbHolder[r] = m
    /\ believes[m] = r
    /\ arbHolder' = [arbHolder EXCEPT ![r] = NONE]
    /\ believes'  = [believes  EXCEPT ![m] = NONE]
    /\ UNCHANGED <<arbEpoch, token>>

\* PARTITION / lost release: the arbiter reclaims r (lease timeout / preemption)
\* but the notification to the holder is lost, so the holder keeps believing.
ExpireLostNotify(r) ==
    /\ arbHolder[r] /= NONE
    /\ arbHolder' = [arbHolder EXCEPT ![r] = NONE]
    /\ UNCHANGED <<arbEpoch, believes, token>>

\* ARBITER CRASH + RESTART: the arbiter loses its VOLATILE holder map (every
\* resource appears free after restart). Machines are unaware -- their beliefs and
\* tokens are unchanged (a pre-crash holder still believes it holds, with its old
\* token). The epoch survives iff it was on stable storage (PersistEpoch); otherwise
\* it resets to 0 and a later re-grant can collide with a stale token.
CrashRestart ==
    /\ \E r \in Resources : arbHolder[r] /= NONE          \* something to lose (bounds the search)
    /\ arbHolder' = [r \in Resources |-> NONE]
    /\ arbEpoch'  = IF PersistEpoch THEN arbEpoch ELSE [r \in Resources |-> 0]
    /\ UNCHANGED <<believes, token>>

\* Recovery: a machine that is no longer the arbiter's holder eventually drops its
\* stale belief (heartbeat reconciliation). Models recovery and bounds the state.
ClearStaleBelief(m) ==
    /\ believes[m] /= NONE
    /\ arbHolder[believes[m]] /= m
    /\ believes' = [believes EXCEPT ![m] = NONE]
    /\ UNCHANGED <<arbHolder, arbEpoch, token>>

Next ==
    \/ \E m \in Machines, r \in Resources : Grant(m, r)
    \/ \E m \in Machines, r \in Resources : Release(m, r)
    \/ \E r \in Resources : ExpireLostNotify(r)
    \/ CrashRestart
    \/ \E m \in Machines : ClearStaleBelief(m)

Spec == Init /\ [][Next]_vars

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
\* Holds iff PersistEpoch = TRUE: a persisted monotonic epoch fences every pre-crash
\* holder after restart; a volatile (reset) epoch lets a re-grant collide with a
\* stale token and two machines actuate the same load point.
THEOREM Spec => []ExclusiveActuation

================================================================================
