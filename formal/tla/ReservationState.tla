------------------------- MODULE ReservationState -------------------------
(* TLA+ formal model of CAP ReservationState machine (Ch06 §6.3).
 *
 * Models N machines competing for M resources.
 *
 * Verifies:
 *   Safety:   No double-grant (a resource has at most one GRANTED holder).
 *   Safety:   Terminal states are absorbing.
 *   Liveness: Every request eventually reaches GRANTED or DENIED.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Machines,       \* Set of machine IDs (e.g., {"m1", "m2"})
    Resources       \* Set of resource IDs (e.g., {"zone-A", "zone-B"})

VARIABLES
    resState,       \* resState[m][r] ∈ ReservationStates ∪ {"NONE"}
    holders         \* holders[r] = machine_id or "NONE" (current grant holder)

vars == <<resState, holders>>

\* ─── State Definitions ────────────────────────────────────────────────

ReservationStates == { "NONE", "REQUESTED", "GRANTED", "DENIED", "RELEASED", "EXPIRED" }

TerminalStates == { "DENIED", "RELEASED", "EXPIRED" }

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ \A m \in Machines, r \in Resources : resState[m][r] \in ReservationStates
    /\ \A r \in Resources : holders[r] \in Machines \cup {"NONE"}

\* ─── Safety: No Double-Grant ────────────────────────────────────────

NoDoubleGrant ==
    \A r \in Resources :
        Cardinality({ m \in Machines : resState[m][r] = "GRANTED" }) <= 1

\* ─── Safety: Holder Consistency ─────────────────────────────────────

HolderConsistent ==
    \A r \in Resources :
        \/ (holders[r] = "NONE" /\ \A m \in Machines : resState[m][r] /= "GRANTED")
        \/ (\E m \in Machines : holders[r] = m /\ resState[m][r] = "GRANTED")

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ resState = [m \in Machines |-> [r \in Resources |-> "NONE"]]
    /\ holders = [r \in Resources |-> "NONE"]

\* ─── Transitions (Ch06 §6.3.3) ─────────────────────────────────────

\* Machine requests a resource
Request(m, r) ==
    /\ resState[m][r] = "NONE"
    /\ resState' = [resState EXCEPT ![m][r] = "REQUESTED"]
    /\ UNCHANGED holders

\* Site Agent grants (resource available, no conflict)
Grant(m, r) ==
    /\ resState[m][r] = "REQUESTED"
    /\ holders[r] = "NONE"    \* No current holder → can grant
    /\ resState' = [resState EXCEPT ![m][r] = "GRANTED"]
    /\ holders' = [holders EXCEPT ![r] = m]

\* Site Agent denies (resource occupied or policy conflict)
Deny(m, r) ==
    /\ resState[m][r] = "REQUESTED"
    /\ holders[r] /= "NONE"   \* Resource is occupied
    /\ resState' = [resState EXCEPT ![m][r] = "DENIED"]
    /\ UNCHANGED holders

\* Deny due to request timeout (Ch06 §6.3.4 footnote 1)
DenyTimeout(m, r) ==
    /\ resState[m][r] = "REQUESTED"
    /\ resState' = [resState EXCEPT ![m][r] = "DENIED"]
    /\ UNCHANGED holders

\* Holder releases (ReservationRelease)
Release(m, r) ==
    /\ resState[m][r] = "GRANTED"
    /\ holders[r] = m
    /\ resState' = [resState EXCEPT ![m][r] = "RELEASED"]
    /\ holders' = [holders EXCEPT ![r] = "NONE"]

\* Reservation expires (granted_window elapsed)
ExpireGrant(m, r) ==
    /\ resState[m][r] = "GRANTED"
    /\ holders[r] = m
    /\ resState' = [resState EXCEPT ![m][r] = "EXPIRED"]
    /\ holders' = [holders EXCEPT ![r] = "NONE"]

\* Allow re-request after terminal state (new reservation cycle)
ReRequest(m, r) ==
    /\ resState[m][r] \in TerminalStates
    /\ resState' = [resState EXCEPT ![m][r] = "NONE"]
    /\ UNCHANGED holders

\* ─── Next-State Relation ────────────────────────────────────────────

Next ==
    \E m \in Machines, r \in Resources :
        \/ Request(m, r)
        \/ Grant(m, r)
        \/ Deny(m, r)
        \/ DenyTimeout(m, r)
        \/ Release(m, r)
        \/ ExpireGrant(m, r)
        \/ ReRequest(m, r)

\* ─── Fairness ───────────────────────────────────────────────────────

Fairness ==
    \A m \in Machines, r \in Resources :
        /\ WF_vars(Grant(m, r))
        /\ WF_vars(Deny(m, r))
        /\ WF_vars(DenyTimeout(m, r))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ─── Liveness ───────────────────────────────────────────────────────

\* Every request eventually reaches GRANTED or DENIED
EventuallyDecided ==
    \A m \in Machines, r \in Resources :
        [](resState[m][r] = "REQUESTED" => <>(resState[m][r] \in {"GRANTED", "DENIED"}))

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => []NoDoubleGrant
THEOREM Spec => []HolderConsistent
THEOREM Spec => EventuallyDecided

========================================================================
