------------------------ MODULE CAPCoordination ------------------------
(* TLA+ composite model: multi-machine CAP coordination.
 *
 * Models a set of excavators and carriers (dumps) contending for a set of
 * shared load-point resources, combining the TaskState and
 * ReservationState machines into a single concurrent specification.
 *
 * The model is parameterised so that the same specification covers the
 * minimal reference instance and a bounded scalability sweep:
 *   Excavators, Dumps  -- the machine sets (N = |Excavators| + |Dumps|)
 *   Resources          -- the shared resource set (R = |Resources|)
 *   MaxTasks           -- per-machine completed-task counter saturates here
 *                         (keeps the state space finite WITHOUT a state
 *                          constraint, so liveness checking is sound)
 *   QueuedGrants       -- FALSE: a busy resource bounces a request (deny);
 *                         TRUE : a busy resource queues the request (the
 *                                requester waits in REQUESTED until grantable)
 *
 * Verifies:
 *   Safety:   No deadlock -- at least one machine can always make progress.
 *   Safety:   No resource ever has two simultaneous GRANTED holders.
 *   Safety:   Reservation + holder + target consistency.
 *   Liveness: No starvation -- every machine eventually completes a task
 *             (sound only under the appropriate fairness/queueing regime;
 *              see ReservationState/MachineMode for the component liveness).
 *)

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
    Excavators,     \* e.g., {"exc1", "exc2"}
    Dumps,          \* e.g., {"dump1"}
    Resources,      \* e.g., {"LP-1"} or {"LP-1", "LP-2"}
    MaxTasks,       \* saturation bound for the per-machine task counter
    QueuedGrants    \* BOOLEAN: TRUE = site agent queues instead of denying

\* All machines
Machines == Excavators \cup Dumps

VARIABLES
    taskState,      \* taskState[m] in TaskStates
    resState,       \* resState[m] in ResStates (single outstanding reservation)
    resTarget,      \* resTarget[m] in Resources \cup {"NONE"}: the resource m targets
    holder,         \* holder[r] in Machines \cup {"NONE"}: current grant holder of r
    taskCount       \* taskCount[m] = completed-task count (saturating, for starvation)

vars == <<taskState, resState, resTarget, holder, taskCount>>

\* Symmetry: machines of the same role and resources are interchangeable.
\* (Sound for SAFETY checking only; never used in liveness configurations.)
Symm == Permutations(Excavators) \cup Permutations(Dumps) \cup Permutations(Resources)

\* ─── State Definitions ────────────────────────────────────────────────

TaskStates == { "IDLE", "PENDING", "RUNNING", "BLOCKED", "SUCCEEDED" }

ResStates == { "NONE", "REQUESTED", "GRANTED", "DENIED", "RELEASED" }

\* ─── State Constraint (legacy regression only) ───────────────────────

BoundedTaskCount == \A m \in Machines : taskCount[m] <= 2

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ \A m \in Machines : taskState[m] \in TaskStates
    /\ \A m \in Machines : resState[m] \in ResStates
    /\ resTarget \in [Machines -> Resources \cup {"NONE"}]
    /\ holder \in [Resources -> Machines \cup {"NONE"}]
    /\ \A m \in Machines : taskCount[m] \in 0..MaxTasks

\* ─── Safety Properties ──────────────────────────────────────────────

\* No resource has two simultaneous GRANTED holders (no double-grant).
NoDoubleGrant ==
    \A r \in Resources :
        Cardinality({ m \in Machines :
                        resState[m] = "GRANTED" /\ resTarget[m] = r }) <= 1

\* Holder tracking is consistent with reservation state, per resource.
HolderConsistent ==
    \A r \in Resources :
        \/ (holder[r] = "NONE"
              /\ \A m \in Machines :
                   ~(resState[m] = "GRANTED" /\ resTarget[m] = r))
        \/ (\E m \in Machines :
                holder[r] = m /\ resState[m] = "GRANTED" /\ resTarget[m] = r)

\* A machine holds a resource target exactly while a reservation exists.
TargetConsistent ==
    \A m \in Machines : (resState[m] = "NONE") <=> (resTarget[m] = "NONE")

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ taskState = [m \in Machines |-> "IDLE"]
    /\ resState  = [m \in Machines |-> "NONE"]
    /\ resTarget = [m \in Machines |-> "NONE"]
    /\ holder    = [r \in Resources |-> "NONE"]
    /\ taskCount = [m \in Machines |-> 0]

\* ─── Task Transitions ───────────────────────────────────────────────

\* Site agent dispatches a WorkOrder
DispatchTask(m) ==
    /\ taskState[m] = "IDLE"
    /\ taskState' = [taskState EXCEPT ![m] = "PENDING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount>>

\* Machine accepts the task
AcceptTask(m) ==
    /\ taskState[m] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount>>

\* Machine needs a resource → request reservation on r
RequestResource(m, r) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ resState'  = [resState  EXCEPT ![m] = "REQUESTED"]
    /\ resTarget' = [resTarget EXCEPT ![m] = r]
    /\ UNCHANGED <<taskState, holder, taskCount>>

\* Site agent grants the targeted resource (it is free)
GrantResource(m) ==
    /\ resState[m] = "REQUESTED"
    /\ holder[resTarget[m]] = "NONE"
    /\ resState' = [resState EXCEPT ![m] = "GRANTED"]
    /\ holder'   = [holder EXCEPT ![resTarget[m]] = m]
    /\ UNCHANGED <<taskState, resTarget, taskCount>>

\* Site agent denies (another machine holds the targeted resource).
\* Disabled when the site agent queues requests instead of bouncing them.
DenyResource(m) ==
    /\ ~QueuedGrants
    /\ resState[m] = "REQUESTED"
    /\ holder[resTarget[m]] /= "NONE"
    /\ resState' = [resState EXCEPT ![m] = "DENIED"]
    /\ UNCHANGED <<taskState, resTarget, holder, taskCount>>

\* Denied machine transitions to BLOCKED and clears its target for re-request.
\* (Enabled from RUNNING or BLOCKED: a machine denied again after a retry must
\*  still be able to leave the DENIED state -- otherwise BLOCKED/DENIED is an
\*  absorbing trap. This repairs a defect found during the sweep.)
BlockOnDenial(m) ==
    /\ taskState[m] \in {"RUNNING", "BLOCKED"}
    /\ resState[m] = "DENIED"
    /\ taskState' = [taskState EXCEPT ![m] = "BLOCKED"]
    /\ resState'  = [resState  EXCEPT ![m] = "NONE"]
    /\ resTarget' = [resTarget EXCEPT ![m] = "NONE"]
    /\ UNCHANGED <<holder, taskCount>>

\* Blocked machine retries the reservation (may re-target any resource)
RetryReservation(m, r) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "NONE"
    /\ resState'  = [resState  EXCEPT ![m] = "REQUESTED"]
    /\ resTarget' = [resTarget EXCEPT ![m] = r]
    /\ UNCHANGED <<taskState, holder, taskCount>>

\* Blocked machine gets unblocked (reservation granted)
UnblockOnGrant(m) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "GRANTED"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount>>

\* Saturating increment of the completed-task counter
Inc(c) == IF c < MaxTasks THEN c + 1 ELSE c

\* Machine completes task and releases its resource
CompleteTask(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "GRANTED"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ resState'  = [resState  EXCEPT ![m] = "RELEASED"]
    /\ holder'    = [holder EXCEPT ![resTarget[m]] = "NONE"]
    /\ taskCount' = [taskCount EXCEPT ![m] = Inc(@)]
    /\ UNCHANGED resTarget

\* Machine completes without needing a resource (e.g., pure hauling leg)
CompleteWithoutResource(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ taskCount' = [taskCount EXCEPT ![m] = Inc(@)]
    /\ UNCHANGED <<resState, resTarget, holder>>

\* Reset after completion (ready for next cycle)
ResetTask(m) ==
    /\ taskState[m] = "SUCCEEDED"
    /\ resState[m] \in {"RELEASED", "NONE"}
    /\ taskState' = [taskState EXCEPT ![m] = "IDLE"]
    /\ resState'  = [resState  EXCEPT ![m] = "NONE"]
    /\ resTarget' = [resTarget EXCEPT ![m] = "NONE"]
    /\ UNCHANGED <<holder, taskCount>>

\* ─── Next-State Relation ────────────────────────────────────────────

Next ==
    \E m \in Machines :
        \/ DispatchTask(m)
        \/ AcceptTask(m)
        \/ \E r \in Resources : RequestResource(m, r)
        \/ GrantResource(m)
        \/ DenyResource(m)
        \/ BlockOnDenial(m)
        \/ \E r \in Resources : RetryReservation(m, r)
        \/ UnblockOnGrant(m)
        \/ CompleteTask(m)
        \/ CompleteWithoutResource(m)
        \/ ResetTask(m)

\* ─── Fairness ───────────────────────────────────────────────────────

FairnessWeak ==
    \A m \in Machines :
        /\ WF_vars(GrantResource(m))
        /\ WF_vars(DenyResource(m))
        /\ WF_vars(AcceptTask(m))
        /\ WF_vars(UnblockOnGrant(m))
        /\ WF_vars(BlockOnDenial(m))
        /\ SF_vars(CompleteTask(m))
        /\ SF_vars(CompleteWithoutResource(m))
        /\ WF_vars(ResetTask(m))
        /\ SF_vars(DispatchTask(m))
        /\ WF_vars(\E r \in Resources : RetryReservation(m, r))

\* Strongly fair site agent on the grant action (used for the queued-grant
\* no-starvation result): a continuously grantable request is eventually granted.
FairnessStrong ==
    \A m \in Machines :
        /\ SF_vars(GrantResource(m))
        /\ WF_vars(DenyResource(m))
        /\ WF_vars(AcceptTask(m))
        /\ WF_vars(UnblockOnGrant(m))
        /\ WF_vars(BlockOnDenial(m))
        /\ SF_vars(CompleteTask(m))
        /\ SF_vars(CompleteWithoutResource(m))
        /\ WF_vars(ResetTask(m))
        /\ SF_vars(DispatchTask(m))
        /\ WF_vars(\E r \in Resources : RetryReservation(m, r))

Spec       == Init /\ [][Next]_vars /\ FairnessWeak
SpecStrong == Init /\ [][Next]_vars /\ FairnessStrong

\* ─── Liveness: No Starvation ────────────────────────────────────────

\* Every machine eventually completes at least one task.
NoStarvation ==
    \A m \in Machines : <>(taskCount[m] > 0)

\* Stronger: under perpetual operation, every machine reaches SUCCEEDED
\* infinitely often (no machine is permanently shut out of the resource).
AlwaysEventuallyCompletes ==
    \A m \in Machines : []<>(taskState[m] = "SUCCEEDED")

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => []NoDoubleGrant
THEOREM Spec => []HolderConsistent
THEOREM Spec => []TargetConsistent

========================================================================
