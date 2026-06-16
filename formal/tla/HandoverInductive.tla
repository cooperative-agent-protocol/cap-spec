---------------------------- MODULE HandoverInductive ----------------------------
(* Apalache (symbolic / SMT) INDUCTIVE-INVARIANT verification of the HANDOVER
 * receiver-ownership property (P4): throughout a machine-to-machine handover's
 * IN_PROGRESS window, the handover-point resource is held exclusively by the
 * receiver, never momentarily unheld. This is the unbounded-by-induction
 * counterpart of the explicit-state CAPCoordination P4 result, and the third
 * inductive invariant alongside ReservationInductive (no-double-grant) and
 * FencingInductive (fencing exclusivity).
 *
 * It models the ATOMIC ownership-transfer discipline (BeginHandoverAtomic):
 * the sender releases r and the receiver is granted r in ONE step, so the
 * holder of r passes sender -> receiver with no intervening free window. Plain
 * acquire/release of r are guarded to be disabled while a handover on r is
 * active, which is what makes ownership inductive: nothing can grab r mid-
 * handover. (The naive release-then-reacquire discipline, which TLC shows
 * VIOLATES P4, is deliberately not modelled here -- it is not inductive.)
 *
 * Set-valued encoding (a machine's grant and a resource's receiver are sets of
 * size <= 1; empty = none) avoids mixing a sentinel with the uninterpreted
 * MACHINE / RESOURCE types. The holder of r is DERIVED from the grant relation
 * (HolderSet(r) == { m : r \in granted[m] }), so holder/grant consistency is
 * structural rather than a maintained invariant.
 *
 * Checks (see RESULTS.md for the exact apalache-mc invocations):
 *   base:  Init    => IndInv          (apalache check --init=Init  --inv=IndInv --length=0)
 *   step:  IndInv /\ Next => IndInv'  (apalache check --init=IndInv --inv=IndInv --length=1)
 * Both pass  ==>  ReceiverOwnership holds in all reachable states, any fleet size.
 *)

EXTENDS Integers, FiniteSets, Apalache

CONSTANTS
    \* @type: Set(MACHINE);
    Machines,
    \* @type: Set(RESOURCE);
    Resources

VARIABLES
    \* @type: MACHINE -> Set(RESOURCE);
    granted,      \* resource a machine currently holds GRANTED (<= 1); empty = none
    \* @type: MACHINE -> Set(RESOURCE);
    requested,    \* resource a machine has REQUESTED and is waiting for (<= 1)
    \* @type: RESOURCE -> Str;
    hoState,      \* handover flow state per resource
    \* @type: RESOURCE -> Set(MACHINE);
    receiverOf    \* the handover receiver for a resource (<= 1); empty = none

ConstInit ==
    /\ Machines = Gen(4)
    /\ Resources = Gen(4)

HandoverStates == { "NONE", "REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS", "COMPLETED" }

\* The (derived) set of machines that hold r GRANTED -- the holder of r.
\* @type: (RESOURCE) => Set(MACHINE);
HolderSet(r) == { m \in Machines : r \in granted[m] }

TypeOK ==
    /\ granted    \in [Machines -> SUBSET Resources]
    /\ requested  \in [Machines -> SUBSET Resources]
    /\ hoState    \in [Resources -> HandoverStates]
    /\ receiverOf \in [Resources -> SUBSET Machines]

Init ==
    /\ granted    = [m \in Machines |-> {}]
    /\ requested  = [m \in Machines |-> {}]
    /\ hoState    = [r \in Resources |-> "NONE"]
    /\ receiverOf = [r \in Resources |-> {}]

\* ─── Supporting (singleton) invariants ──────────────────────────────────────
Singletons ==
    /\ \A m \in Machines  : Cardinality(granted[m])    <= 1
    /\ \A m \in Machines  : Cardinality(requested[m])  <= 1
    /\ \A r \in Resources : Cardinality(receiverOf[r]) <= 1

\* No resource is held GRANTED by two machines (no-double-grant over the
\* derived holder relation).
NoDoubleGrant ==
    \A r \in Resources : Cardinality(HolderSet(r)) <= 1

\* ─── The target safety property: P4 receiver ownership ───────────────────────
\* While a handover on r is IN_PROGRESS, r is held by the receiver (and, with
\* NoDoubleGrant, by the receiver ALONE), so r is never momentarily unheld.
ReceiverOwnership ==
    \A r \in Resources :
        (hoState[r] = "IN_PROGRESS") =>
            \E rcv \in Machines :
                /\ receiverOf[r] = {rcv}
                /\ r \in granted[rcv]

\* ─── Transitions ─────────────────────────────────────────────────────────────

\* A machine requests a (possibly held) resource and queues for it.
Request(m, r) ==
    /\ granted[m] = {}
    /\ requested[m] = {}
    /\ requested' = [requested EXCEPT ![m] = {r}]
    /\ UNCHANGED <<granted, hoState, receiverOf>>

\* Ordinary grant of a FREE resource (no handover active on it).
Acquire(m, r) ==
    /\ r \in requested[m]
    /\ HolderSet(r) = {}
    /\ granted[m] = {}
    /\ hoState[r] = "NONE"
    /\ granted'   = [granted   EXCEPT ![m] = {r}]
    /\ requested' = [requested EXCEPT ![m] = {}]
    /\ UNCHANGED <<hoState, receiverOf>>

\* Plain release -- DISABLED while a handover on r is active (hoState # NONE),
\* so the holder cannot unilaterally vacate mid-handover.
ReleasePlain(m, r) ==
    /\ r \in granted[m]
    /\ hoState[r] = "NONE"
    /\ granted' = [granted EXCEPT ![m] = {}]
    /\ UNCHANGED <<requested, hoState, receiverOf>>

\* Holder s of r offers a handover to a machine rcv waiting (REQUESTED) for r.
InitiateHandover(s, r, rcv) ==
    /\ hoState[r] = "NONE"
    /\ r \in granted[s]
    /\ rcv /= s
    /\ r \in requested[rcv]
    /\ hoState'    = [hoState    EXCEPT ![r] = "REQUESTED"]
    /\ receiverOf' = [receiverOf EXCEPT ![r] = {rcv}]
    /\ UNCHANGED <<granted, requested>>

AckHandover(r) ==
    /\ hoState[r] = "REQUESTED"
    /\ hoState' = [hoState EXCEPT ![r] = "ACKNOWLEDGED"]
    /\ UNCHANGED <<granted, requested, receiverOf>>

\* ATOMIC ownership transfer: sender releases r and receiver is granted r in ONE
\* step; holder(r) passes sender -> receiver with no free window. This single-
\* step transfer is what makes ReceiverOwnership inductive.
BeginHandoverAtomic(s, r, rcv) ==
    /\ hoState[r] = "ACKNOWLEDGED"
    /\ receiverOf[r] = {rcv}
    /\ r \in granted[s]
    /\ s /= rcv
    /\ granted[rcv] = {}
    /\ granted'   = [granted EXCEPT ![s] = {}, ![rcv] = {r}]
    /\ requested' = [requested EXCEPT ![rcv] = {}]
    /\ hoState'   = [hoState EXCEPT ![r] = "IN_PROGRESS"]
    /\ UNCHANGED <<receiverOf>>

CompleteHandover(r, rcv) ==
    /\ hoState[r] = "IN_PROGRESS"
    /\ receiverOf[r] = {rcv}
    /\ r \in granted[rcv]
    /\ hoState' = [hoState EXCEPT ![r] = "COMPLETED"]
    /\ UNCHANGED <<granted, requested, receiverOf>>

CleanupHandover(r) ==
    /\ hoState[r] = "COMPLETED"
    /\ hoState'    = [hoState    EXCEPT ![r] = "NONE"]
    /\ receiverOf' = [receiverOf EXCEPT ![r] = {}]
    /\ UNCHANGED <<granted, requested>>

Next ==
    \/ \E m \in Machines : \E r \in Resources : Request(m, r)
    \/ \E m \in Machines : \E r \in Resources : Acquire(m, r)
    \/ \E m \in Machines : \E r \in Resources : ReleasePlain(m, r)
    \/ \E s \in Machines : \E r \in Resources : \E rcv \in Machines : InitiateHandover(s, r, rcv)
    \/ \E r \in Resources : AckHandover(r)
    \/ \E s \in Machines : \E r \in Resources : \E rcv \in Machines : BeginHandoverAtomic(s, r, rcv)
    \/ \E r \in Resources : \E rcv \in Machines : CompleteHandover(r, rcv)
    \/ \E r \in Resources : CleanupHandover(r)

\* ─── Inductive invariant ─────────────────────────────────────────────────────
IndInv ==
    /\ TypeOK
    /\ Singletons
    /\ NoDoubleGrant
    /\ ReceiverOwnership

\* Non-vacuity sanity: "no handover is ever IN_PROGRESS" is true at Init but is
\* NOT preserved by BeginHandoverAtomic, so its inductive STEP must FAIL --
\* confirming the SMT check discriminates (the positive result is not vacuous).
NotInductive ==
    /\ TypeOK
    /\ \A r \in Resources : hoState[r] /= "IN_PROGRESS"

================================================================================
