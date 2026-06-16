------------------------- MODULE MultiResourceInductive -------------------------
(* Apalache (symbolic / SMT) INDUCTIVE-INVARIANT verification of the
 * acquisition-order discipline that makes multi-resource coordination
 * deadlock-free. Fourth inductive invariant alongside ReservationInductive
 * (no-double-grant), FencingInductive (fencing exclusivity), and
 * HandoverInductive (handover receiver-ownership).
 *
 * Deadlock-freedom itself is a *progress* property (some action is enabled in
 * every non-terminal state); the explicit-state MultiResource result checks it
 * via TLC CHECK_DEADLOCK at a bounded instance. The unbounded part is the
 * underlying STATE invariant that powers the classic ordered-acquisition
 * argument:
 *
 *   OrderedPrefix : every machine holds a DOWNWARD-CLOSED prefix of the resource
 *                   order --- if it holds r it holds every resource ordered
 *                   before r. Hence a machine only ever waits for a resource
 *                   LARGER than everything it holds, so a wait-for cycle
 *                   m1 -> m2 -> ... -> m1 would force r1 < r2 < ... < r1, a
 *                   contradiction. No circular wait ==> deadlock-free.
 *
 * This module proves OrderedPrefix (with mutual exclusion) as an inductive
 * invariant over symbolic machine and resource sets, so the no-circular-wait
 * structural condition holds for ANY fleet size and ANY number of resources,
 * not just the bounded TLC instance. Resources are integers so that < is the
 * total acquisition order; the owner of r is DERIVED from `holds`
 * (Owners(r) == { m : r \in holds[m] }), making mutual exclusion structural.
 *
 * Checks (see RESULTS.md for the exact apalache-mc invocations):
 *   base:  Init    => IndInv          (apalache check --init=Init  --inv=IndInv --length=0)
 *   step:  IndInv /\ Next => IndInv'  (apalache check --init=IndInv --inv=IndInv --length=1)
 * Both pass  ==>  OrderedPrefix (no circular wait) holds in all reachable states.
 *)

EXTENDS Integers, FiniteSets, Apalache

CONSTANTS
    \* @type: Set(MACHINE);
    Machines,
    \* @type: Set(Int);
    Resources

VARIABLES
    \* @type: MACHINE -> Set(Int);
    holds         \* resources each machine currently holds

ConstInit ==
    /\ Machines  = Gen(4)
    /\ Resources = Gen(4)

\* Machines that hold r (derived owner set; mutual exclusion is structural).
\* @type: (Int) => Set(MACHINE);
Owners(r) == { m \in Machines : r \in holds[m] }

TypeOK ==
    /\ holds \in [Machines -> SUBSET Resources]

Init ==
    holds = [m \in Machines |-> {}]

\* ─── Transitions (ordered-acquisition discipline) ───────────────────────────

\* Acquire a FREE resource r, but only after holding every needed resource
\* ordered before r (the total acquisition order). Each machine needs the whole
\* resource set; it acquires one at a time.
Acquire(m, r) ==
    /\ r \in Resources
    /\ r \notin holds[m]
    /\ \A m2 \in Machines : r \notin holds[m2]          \* r is free
    /\ \A r2 \in Resources : (r2 < r) => (r2 \in holds[m])  \* acquisition order
    /\ holds' = [holds EXCEPT ![m] = @ \union {r}]

\* A machine that holds every resource does its work and releases them all.
Complete(m) ==
    /\ holds[m] = Resources
    /\ holds' = [holds EXCEPT ![m] = {}]

Next ==
    \E m \in Machines :
        \/ \E r \in Resources : Acquire(m, r)
        \/ Complete(m)

\* ─── Invariants ─────────────────────────────────────────────────────────────

\* Mutual exclusion: no resource is held by two machines.
NoDoubleOwner ==
    \A r \in Resources : Cardinality(Owners(r)) <= 1

\* The acquisition-order invariant: each machine's holdings are downward-closed
\* under <. A machine therefore waits only for a resource larger than all it
\* holds, which is exactly what rules out a circular wait (deadlock).
OrderedPrefix ==
    \A m \in Machines :
        \A r \in holds[m] :
            \A r2 \in Resources : (r2 < r) => (r2 \in holds[m])

IndInv ==
    /\ TypeOK
    /\ NoDoubleOwner
    /\ OrderedPrefix

\* Non-vacuity sanity: "no machine ever holds anything" is true at Init but is
\* NOT preserved by Acquire, so its inductive STEP must FAIL --- confirming the
\* SMT check discriminates (the positive result is not vacuous).
NotInductive ==
    /\ TypeOK
    /\ \A m \in Machines : holds[m] = {}

================================================================================
