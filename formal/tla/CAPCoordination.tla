------------------------ MODULE CAPCoordination ------------------------
(* TLA+ composite model: multi-machine CAP coordination.
 *
 * Models 2 excavators + 1 dump truck contending for a shared load point.
 * Combines TaskState and ReservationState machines.
 *
 * Verifies:
 *   Safety:   No deadlock — at least one machine can always make progress.
 *   Safety:   Load point never has two simultaneous holders.
 *   Safety:   Reservation + task state consistency.
 *   Liveness: No starvation — every machine eventually completes a task.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Excavators,     \* e.g., {"exc1", "exc2"}
    Dumps,          \* e.g., {"dump1"}
    LoadPoint       \* e.g., "LP-1" (single shared resource)

\* All machines
Machines == Excavators \cup Dumps

VARIABLES
    taskState,      \* taskState[m] ∈ TaskStates
    resState,       \* resState[m] ∈ ReservationStates  (for LoadPoint)
    lpHolder,       \* Current holder of LoadPoint ("NONE" or machine_id)
    taskCount       \* taskCount[m] = number of completed tasks (for starvation check)

vars == <<taskState, resState, lpHolder, taskCount>>

\* ─── State Definitions ────────────────────────────────────────────────

TaskStates == { "IDLE", "PENDING", "RUNNING", "BLOCKED", "SUCCEEDED" }

ResStates == { "NONE", "REQUESTED", "GRANTED", "DENIED", "RELEASED" }

\* ─── State Constraint (for model checking) ───────────────────────────

BoundedTaskCount == \A m \in Machines : taskCount[m] <= 2

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ \A m \in Machines : taskState[m] \in TaskStates
    /\ \A m \in Machines : resState[m] \in ResStates
    /\ lpHolder \in Machines \cup {"NONE"}
    /\ \A m \in Machines : taskCount[m] \in 0..3

\* ─── Safety Properties ──────────────────────────────────────────────

\* Load point has at most one holder
NoDoubleGrant ==
    Cardinality({ m \in Machines : resState[m] = "GRANTED" }) <= 1

\* Holder consistency
HolderConsistent ==
    \/ (lpHolder = "NONE" /\ \A m \in Machines : resState[m] /= "GRANTED")
    \/ (\E m \in Machines : lpHolder = m /\ resState[m] = "GRANTED")

\* No global deadlock: at least one action is always possible
\* (This is checked by TLC automatically as a deadlock check)

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ taskState = [m \in Machines |-> "IDLE"]
    /\ resState = [m \in Machines |-> "NONE"]
    /\ lpHolder = "NONE"
    /\ taskCount = [m \in Machines |-> 0]

\* ─── Task Transitions ───────────────────────────────────────────────

\* Site agent dispatches a WorkOrder
DispatchTask(m) ==
    /\ taskState[m] = "IDLE"
    /\ taskState' = [taskState EXCEPT ![m] = "PENDING"]
    /\ UNCHANGED <<resState, lpHolder, taskCount>>

\* Machine accepts the task
AcceptTask(m) ==
    /\ taskState[m] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, lpHolder, taskCount>>

\* Machine needs load point → request reservation
RequestLoadPoint(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ resState' = [resState EXCEPT ![m] = "REQUESTED"]
    /\ UNCHANGED <<taskState, lpHolder, taskCount>>

\* Site agent grants load point
GrantLoadPoint(m) ==
    /\ resState[m] = "REQUESTED"
    /\ lpHolder = "NONE"
    /\ resState' = [resState EXCEPT ![m] = "GRANTED"]
    /\ lpHolder' = m
    /\ UNCHANGED <<taskState, taskCount>>

\* Site agent denies (another machine holds it)
DenyLoadPoint(m) ==
    /\ resState[m] = "REQUESTED"
    /\ lpHolder /= "NONE"
    /\ resState' = [resState EXCEPT ![m] = "DENIED"]
    /\ UNCHANGED <<taskState, lpHolder, taskCount>>

\* Denied machine transitions to BLOCKED
BlockOnDenial(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "DENIED"
    /\ taskState' = [taskState EXCEPT ![m] = "BLOCKED"]
    /\ resState' = [resState EXCEPT ![m] = "NONE"]  \* Reset for re-request
    /\ UNCHANGED <<lpHolder, taskCount>>

\* Blocked machine retries reservation
RetryReservation(m) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "NONE"
    /\ resState' = [resState EXCEPT ![m] = "REQUESTED"]
    /\ UNCHANGED <<taskState, lpHolder, taskCount>>

\* Blocked machine gets unblocked (reservation granted)
UnblockOnGrant(m) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "GRANTED"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, lpHolder, taskCount>>

\* Machine completes task and releases load point
CompleteTask(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "GRANTED"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ resState' = [resState EXCEPT ![m] = "RELEASED"]
    /\ lpHolder' = "NONE"
    /\ taskCount' = [taskCount EXCEPT ![m] = taskCount[m] + 1]

\* Machine completes without needing load point (e.g., pure hauling leg)
CompleteWithoutLP(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ taskCount' = [taskCount EXCEPT ![m] = taskCount[m] + 1]
    /\ UNCHANGED <<resState, lpHolder>>

\* Reset after completion (ready for next cycle)
ResetTask(m) ==
    /\ taskState[m] = "SUCCEEDED"
    /\ resState[m] \in {"RELEASED", "NONE"}
    /\ taskState' = [taskState EXCEPT ![m] = "IDLE"]
    /\ resState' = [resState EXCEPT ![m] = "NONE"]
    /\ UNCHANGED <<lpHolder, taskCount>>

\* ─── Next-State Relation ────────────────────────────────────────────

Next ==
    \E m \in Machines :
        \/ DispatchTask(m)
        \/ AcceptTask(m)
        \/ RequestLoadPoint(m)
        \/ GrantLoadPoint(m)
        \/ DenyLoadPoint(m)
        \/ BlockOnDenial(m)
        \/ RetryReservation(m)
        \/ UnblockOnGrant(m)
        \/ CompleteTask(m)
        \/ CompleteWithoutLP(m)
        \/ ResetTask(m)

\* ─── Fairness ───────────────────────────────────────────────────────

Fairness ==
    \A m \in Machines :
        /\ WF_vars(GrantLoadPoint(m))
        /\ WF_vars(DenyLoadPoint(m))
        /\ WF_vars(AcceptTask(m))
        /\ WF_vars(UnblockOnGrant(m))
        /\ SF_vars(CompleteTask(m))       \* Strong: eventually completes with LP
        /\ SF_vars(CompleteWithoutLP(m))  \* Strong: eventually completes without LP
        /\ WF_vars(ResetTask(m))
        /\ SF_vars(DispatchTask(m))
        /\ WF_vars(RetryReservation(m))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ─── Liveness: No Starvation ────────────────────────────────────────

\* Every machine eventually completes at least one task
NoStarvation ==
    \A m \in Machines : <>(taskCount[m] > 0)

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => []NoDoubleGrant
THEOREM Spec => []HolderConsistent
THEOREM Spec => NoStarvation

========================================================================
