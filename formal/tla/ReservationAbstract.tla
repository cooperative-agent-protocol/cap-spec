--------------------------- MODULE ReservationAbstract ---------------------------
(* The abstract reservation model that CAPCoordination refines (reviewer R2-1).
 *
 * ReservationInductive proves NoDoubleGrant inductive over a model with only Acquire and Release. Mapping
 * CAPCoordination onto it step by step shows one transition it lacks: an atomic hand-over moves a grant from
 * the sender to the receiver in ONE step (BeginHandoverAtomic), which is neither an Acquire nor a Release. This
 * module adds Transfer and is the abstraction checked by CAPCoordinationRefinement.tla (TLC: every
 * CAPCoordination behaviour, mapped by held <- the GRANTED reservations, is a behaviour of this Spec) and by
 * ReservationInductive's inductive check (with Transfer added there too). Disjoint stays inductive: Transfer
 * gives r to a machine only after taking it from its sole holder.
 *)
EXTENDS FiniteSets

CONSTANTS Machines, Resources,
          AllowTransfer   \* BOOLEAN: FALSE = ReservationInductive's original transitions (the gap)

VARIABLES held        \* held[m] \subseteq Resources: the resources m holds GRANTED

TypeOK == held \in [Machines -> SUBSET Resources]

Init == held = [m \in Machines |-> {}]

Acquire(m, r) ==
    /\ \A m2 \in Machines : r \notin held[m2]
    /\ held' = [held EXCEPT ![m] = @ \union {r}]

Release(m, r) ==
    /\ r \in held[m]
    /\ held' = [held EXCEPT ![m] = @ \ {r}]

\* The atomic hand-over: r goes from its holder m to m2 in one step.
Transfer(m, m2, r) ==
    /\ m /= m2
    /\ r \in held[m]
    /\ \A m3 \in Machines \ {m} : r \notin held[m3]
    /\ held' = [held EXCEPT ![m] = @ \ {r}, ![m2] = @ \union {r}]

Next ==
    \E m \in Machines : \E r \in Resources :
        \/ Acquire(m, r)
        \/ Release(m, r)
        \/ (AllowTransfer /\ \E m2 \in Machines : Transfer(m, m2, r))

Spec == Init /\ [][Next]_held

Disjoint ==
    \A m1 \in Machines : \A m2 \in Machines :
        (m1 /= m2) => (held[m1] \cap held[m2] = {})
================================================================================
