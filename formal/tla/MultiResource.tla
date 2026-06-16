----------------------------- MODULE MultiResource -----------------------------
(* TLA+ component model: multi-resource hold-and-wait and the acquisition-order
 * discipline that makes reservation deadlock-free.
 *
 * The composite CAPCoordination tracks a single outstanding reservation per
 * machine, so a machine can never hold one resource while requesting another;
 * it is therefore *structurally* deadlock-free, and CHECK_DEADLOCK over it is a
 * tautology. Real sites have multiple shared resources (several load points,
 * dump zones, shared corridors), where a machine genuinely holds one while
 * waiting for another --- the classic hold-and-wait that admits circular-wait
 * deadlock.
 *
 * This component models that regime directly: every machine needs the whole
 * resource set, acquires resources one at a time, does its work when it holds
 * them all, then releases them. `ResourceOrder` selects the discipline:
 *
 *   ResourceOrder = FALSE : a machine may acquire needed resources in any order
 *                           -> circular wait is reachable (m1 holds r1 and waits
 *                           for r2 while m2 holds r2 and waits for r1) and TLC
 *                           reports a global DEADLOCK.
 *   ResourceOrder = TRUE  : a machine may acquire r only after holding every
 *                           needed resource ordered before r (a total
 *                           acquisition order) -> circular wait is impossible
 *                           and the model is deadlock-free.
 *
 * Resources are naturals so that `<` is the total acquisition order.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Machines,       \* e.g., {"m1", "m2"}
    Resources,      \* a set of naturals, e.g., {1, 2}
    ResourceOrder   \* BOOLEAN: TRUE = enforce the total acquisition order

NoMachine == "NONE"

VARIABLES
    holds,          \* holds[m] in SUBSET Resources : resources m currently holds
    owner           \* owner[r] in Machines \cup {NoMachine} : current owner of r

vars == <<holds, owner>>

TypeOK ==
    /\ holds \in [Machines -> SUBSET Resources]
    /\ owner \in [Resources -> Machines \cup {NoMachine}]

Init ==
    /\ holds = [m \in Machines |-> {}]
    /\ owner = [r \in Resources |-> NoMachine]

\* holds and owner agree: m holds r iff owner records m as r's owner.
HoldsOwnerConsistent ==
    \A m \in Machines : \A r \in Resources :
        (r \in holds[m]) <=> (owner[r] = m)

\* No resource has two distinct owners (mutual exclusion; holds regardless of
\* the acquisition order -- the ordering buys liveness/deadlock-freedom, not
\* exclusivity).
NoDoubleOwner ==
    \A r \in Resources :
        Cardinality({ m \in Machines : owner[r] = m }) <= 1

\* Each machine needs the whole resource set (the contention case).
Acquire(m, r) ==
    /\ r \notin holds[m]
    /\ owner[r] = NoMachine
    /\ (ResourceOrder => \A r2 \in Resources : (r2 < r) => (r2 \in holds[m]))
    /\ holds' = [holds EXCEPT ![m] = @ \cup {r}]
    /\ owner' = [owner EXCEPT ![r] = m]

\* A machine that holds every resource does its work and releases them all.
Complete(m) ==
    /\ holds[m] = Resources
    /\ holds' = [holds EXCEPT ![m] = {}]
    /\ owner' = [r \in Resources |-> IF owner[r] = m THEN NoMachine ELSE owner[r]]

Next ==
    \E m \in Machines :
        \/ \E r \in Resources : Acquire(m, r)
        \/ Complete(m)

Spec == Init /\ [][Next]_vars

THEOREM Spec => []TypeOK
THEOREM Spec => []HoldsOwnerConsistent
THEOREM Spec => []NoDoubleOwner
\* Deadlock-freedom is checked via TLC CHECK_DEADLOCK: it holds iff
\* ResourceOrder = TRUE; with ResourceOrder = FALSE TLC reaches a circular-wait
\* state with no enabled action.

================================================================================
