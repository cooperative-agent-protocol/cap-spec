------------------------ MODULE CAPCoordination ------------------------
(* TLA+ composite model: multi-machine CAP coordination.
 *
 * Models a set of excavators and carriers (dumps) contending for a set of
 * shared load-point resources, combining the TaskState and
 * ReservationState machines into a single concurrent specification, plus a
 * machine-to-machine resource Handover sub-protocol (excavator hands the
 * load point directly to a waiting carrier).
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
 *   EnableHandover     -- FALSE: no handover sub-protocol (the safety/liveness
 *                                sweep reproduces the reservation-only result);
 *                         TRUE : a holder may hand its resource directly to a
 *                                waiting requester (load-point handover).
 *   AtomicHandover     -- TRUE : ownership transfers sender->receiver in ONE
 *                                step (the resource is never momentarily free);
 *                         FALSE: release-then-regrant (a naive design with a
 *                                transient free window) -- used to show that
 *                                non-atomic handover VIOLATES receiver
 *                                ownership (P4), a first-class negative result.
 *
 * Verifies:
 *   Safety:   No deadlock -- at least one machine can always make progress.
 *   Safety:   No resource ever has two simultaneous GRANTED holders.
 *   Safety:   Reservation + holder + target consistency.
 *   Safety:   Handover receiver ownership (P4) -- throughout a handover's
 *             IN_PROGRESS window the receiver is the unique grant holder of
 *             the handed-over resource.
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
    QueuedGrants,   \* BOOLEAN: TRUE = site agent queues instead of denying
    EnableHandover, \* BOOLEAN: TRUE = enable the machine-to-machine handover
    AtomicHandover  \* BOOLEAN: TRUE = atomic ownership transfer; FALSE = naive

\* All machines
Machines == Excavators \cup Dumps

VARIABLES
    taskState,      \* taskState[m] in TaskStates
    resState,       \* resState[m] in ResStates (single outstanding reservation)
    resTarget,      \* resTarget[m] in Resources \cup {"NONE"}: the resource m targets
    holder,         \* holder[r] in Machines \cup {"NONE"}: current grant holder of r
    taskCount,      \* taskCount[m] = completed-task count (saturating, for starvation)
    hoState,        \* hoState[r] in HandoverStates: handover flow per resource
    hoReceiver      \* hoReceiver[r] in Machines \cup {"NONE"}: the handover receiver

vars == <<taskState, resState, resTarget, holder, taskCount, hoState, hoReceiver>>

\* Symmetry: machines of the same role and resources are interchangeable.
\* (Sound for SAFETY checking only; never used in liveness configurations.)
Symm == Permutations(Excavators) \cup Permutations(Dumps) \cup Permutations(Resources)

\* ─── State Definitions ────────────────────────────────────────────────

TaskStates == { "IDLE", "PENDING", "RUNNING", "BLOCKED", "SUCCEEDED" }

ResStates == { "NONE", "REQUESTED", "GRANTED", "DENIED", "RELEASED" }

HandoverStates == { "NONE", "REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS", "COMPLETED" }

\* ─── State Constraint (legacy regression only) ───────────────────────

BoundedTaskCount == \A m \in Machines : taskCount[m] <= 2

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ \A m \in Machines : taskState[m] \in TaskStates
    /\ \A m \in Machines : resState[m] \in ResStates
    /\ resTarget \in [Machines -> Resources \cup {"NONE"}]
    /\ holder \in [Resources -> Machines \cup {"NONE"}]
    /\ \A m \in Machines : taskCount[m] \in 0..MaxTasks
    /\ hoState \in [Resources -> HandoverStates]
    /\ hoReceiver \in [Resources -> Machines \cup {"NONE"}]

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

\* P4 (handover receiver ownership). Throughout a handover's IN_PROGRESS
\* window the named receiver is the UNIQUE grant holder of the handed-over
\* resource -- there is no instant at which the resource is unheld or held by
\* a third machine while the handover is in progress. This is the literal
\* paper formula: hoState[r] = IN_PROGRESS  =>  exists unique res with
\* res.holder = receiver.
HandoverReceiverOwnership ==
    \A r \in Resources :
        (hoState[r] = "IN_PROGRESS") =>
            /\ hoReceiver[r] /= "NONE"
            /\ holder[r] = hoReceiver[r]
            /\ resState[hoReceiver[r]] = "GRANTED"
            /\ resTarget[hoReceiver[r]] = r
            /\ \A m \in Machines :
                  (resState[m] = "GRANTED" /\ resTarget[m] = r) => (m = hoReceiver[r])

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ taskState  = [m \in Machines |-> "IDLE"]
    /\ resState   = [m \in Machines |-> "NONE"]
    /\ resTarget  = [m \in Machines |-> "NONE"]
    /\ holder     = [r \in Resources |-> "NONE"]
    /\ taskCount  = [m \in Machines |-> 0]
    /\ hoState    = [r \in Resources |-> "NONE"]
    /\ hoReceiver = [r \in Resources |-> "NONE"]

\* ─── Task Transitions ───────────────────────────────────────────────

\* Site agent dispatches a WorkOrder
DispatchTask(m) ==
    /\ taskState[m] = "IDLE"
    /\ taskState' = [taskState EXCEPT ![m] = "PENDING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount, hoState, hoReceiver>>

\* Machine accepts the task
AcceptTask(m) ==
    /\ taskState[m] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount, hoState, hoReceiver>>

\* Machine needs a resource → request reservation on r
RequestResource(m, r) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ resState'  = [resState  EXCEPT ![m] = "REQUESTED"]
    /\ resTarget' = [resTarget EXCEPT ![m] = r]
    /\ UNCHANGED <<taskState, holder, taskCount, hoState, hoReceiver>>

\* Site agent grants the targeted resource (it is free)
GrantResource(m) ==
    /\ resState[m] = "REQUESTED"
    /\ holder[resTarget[m]] = "NONE"
    /\ resState' = [resState EXCEPT ![m] = "GRANTED"]
    /\ holder'   = [holder EXCEPT ![resTarget[m]] = m]
    /\ UNCHANGED <<taskState, resTarget, taskCount, hoState, hoReceiver>>

\* Site agent denies (another machine holds the targeted resource).
\* Disabled when the site agent queues requests instead of bouncing them.
DenyResource(m) ==
    /\ ~QueuedGrants
    /\ resState[m] = "REQUESTED"
    /\ holder[resTarget[m]] /= "NONE"
    /\ resState' = [resState EXCEPT ![m] = "DENIED"]
    /\ UNCHANGED <<taskState, resTarget, holder, taskCount, hoState, hoReceiver>>

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
    /\ UNCHANGED <<holder, taskCount, hoState, hoReceiver>>

\* Blocked machine retries the reservation (may re-target any resource)
RetryReservation(m, r) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "NONE"
    /\ resState'  = [resState  EXCEPT ![m] = "REQUESTED"]
    /\ resTarget' = [resTarget EXCEPT ![m] = r]
    /\ UNCHANGED <<taskState, holder, taskCount, hoState, hoReceiver>>

\* Blocked machine gets unblocked (reservation granted)
UnblockOnGrant(m) ==
    /\ taskState[m] = "BLOCKED"
    /\ resState[m] = "GRANTED"
    /\ taskState' = [taskState EXCEPT ![m] = "RUNNING"]
    /\ UNCHANGED <<resState, resTarget, holder, taskCount, hoState, hoReceiver>>

\* Saturating increment of the completed-task counter
Inc(c) == IF c < MaxTasks THEN c + 1 ELSE c

\* Machine completes task and releases its resource. A holder mid-handover
\* (hoState[resTarget[m]] /= "NONE") may NOT independently release: once a
\* handover is pending the resource is yielded through the handover path, not
\* a unilateral release. (When EnableHandover = FALSE this guard is vacuously
\* true, so the reservation-only sweep is unchanged.)
CompleteTask(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "GRANTED"
    /\ hoState[resTarget[m]] = "NONE"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ resState'  = [resState  EXCEPT ![m] = "RELEASED"]
    /\ holder'    = [holder EXCEPT ![resTarget[m]] = "NONE"]
    /\ taskCount' = [taskCount EXCEPT ![m] = Inc(@)]
    /\ UNCHANGED <<resTarget, hoState, hoReceiver>>

\* Machine completes without needing a resource (e.g., pure hauling leg)
CompleteWithoutResource(m) ==
    /\ taskState[m] = "RUNNING"
    /\ resState[m] = "NONE"
    /\ taskState' = [taskState EXCEPT ![m] = "SUCCEEDED"]
    /\ taskCount' = [taskCount EXCEPT ![m] = Inc(@)]
    /\ UNCHANGED <<resState, resTarget, holder, hoState, hoReceiver>>

\* Reset after completion (ready for next cycle)
ResetTask(m) ==
    /\ taskState[m] = "SUCCEEDED"
    /\ resState[m] \in {"RELEASED", "NONE"}
    /\ taskState' = [taskState EXCEPT ![m] = "IDLE"]
    /\ resState'  = [resState  EXCEPT ![m] = "NONE"]
    /\ resTarget' = [resTarget EXCEPT ![m] = "NONE"]
    /\ UNCHANGED <<holder, taskCount, hoState, hoReceiver>>

\* ─── Handover sub-protocol (Ch06 §6.4, machine-to-machine load-point handover) ───
\* A holder of resource r hands it DIRECTLY to a machine that is waiting for r
\* (queued in REQUESTED), instead of completing-and-releasing -- which would
\* momentarily free r and admit a third machine. All transitions are gated by
\* EnableHandover; BeginHandover branches on AtomicHandover.

\* The holder (sender) of r offers a handover to a machine that has requested r.
\* Models the excavator -> carrier load-point handover at the end of a dig.
InitiateHandover(s, r, rcv) ==
    /\ EnableHandover
    /\ hoState[r] = "NONE"
    /\ holder[r] = s
    /\ resState[s] = "GRANTED"
    /\ resTarget[s] = r
    /\ taskState[s] = "RUNNING"
    /\ rcv /= s
    /\ resState[rcv] = "REQUESTED"
    /\ resTarget[rcv] = r
    /\ hoState'    = [hoState    EXCEPT ![r] = "REQUESTED"]
    /\ hoReceiver' = [hoReceiver EXCEPT ![r] = rcv]
    /\ UNCHANGED <<taskState, resState, resTarget, holder, taskCount>>

\* Receiver acknowledges the offered handover.
AckHandover(r) ==
    /\ EnableHandover
    /\ hoState[r] = "REQUESTED"
    /\ hoState' = [hoState EXCEPT ![r] = "ACKNOWLEDGED"]
    /\ UNCHANGED <<taskState, resState, resTarget, holder, taskCount, hoReceiver>>

\* ATOMIC ownership transfer: sender releases and receiver is granted in ONE
\* step, so holder[r] passes sender -> receiver with no intervening free window.
BeginHandoverAtomic(r) ==
    /\ EnableHandover
    /\ AtomicHandover
    /\ hoState[r] = "ACKNOWLEDGED"
    /\ holder[r] /= "NONE"
    /\ hoReceiver[r] /= "NONE"
    /\ holder[r] /= hoReceiver[r]
    /\ resState[hoReceiver[r]] = "REQUESTED"
    /\ resTarget[hoReceiver[r]] = r
    /\ holder'    = [holder    EXCEPT ![r] = hoReceiver[r]]
    /\ resState'  = [resState  EXCEPT ![holder[r]] = "RELEASED", ![hoReceiver[r]] = "GRANTED"]
    /\ taskState' = [taskState EXCEPT ![holder[r]] = "SUCCEEDED"]
    /\ taskCount' = [taskCount EXCEPT ![holder[r]] = Inc(@)]
    /\ hoState'   = [hoState   EXCEPT ![r] = "IN_PROGRESS"]
    /\ UNCHANGED <<resTarget, hoReceiver>>

\* NAIVE release-then-regrant: the sender releases r (making it momentarily
\* free) and only THEN is the receiver re-granted. The IN_PROGRESS window thus
\* opens with the receiver NOT yet owning r -- and a third machine can grab r
\* in the gap. This branch exists to demonstrate that non-atomic handover
\* violates P4 (HandoverReceiverOwnership).
BeginHandoverNaive(r) ==
    /\ EnableHandover
    /\ ~AtomicHandover
    /\ hoState[r] = "ACKNOWLEDGED"
    /\ holder[r] /= "NONE"
    /\ resState'  = [resState  EXCEPT ![holder[r]] = "RELEASED"]
    /\ taskState' = [taskState EXCEPT ![holder[r]] = "SUCCEEDED"]
    /\ taskCount' = [taskCount EXCEPT ![holder[r]] = Inc(@)]
    /\ holder'    = [holder    EXCEPT ![r] = "NONE"]
    /\ hoState'   = [hoState   EXCEPT ![r] = "IN_PROGRESS"]
    /\ UNCHANGED <<resTarget, hoReceiver>>

\* In the naive regime the receiver must re-grab r after release. (A third
\* machine may beat it to the free resource via ordinary GrantResource, which
\* is exactly the P4 violation.)
GrantToReceiver(r) ==
    /\ EnableHandover
    /\ ~AtomicHandover
    /\ hoState[r] = "IN_PROGRESS"
    /\ holder[r] = "NONE"
    /\ hoReceiver[r] /= "NONE"
    /\ resState[hoReceiver[r]] = "REQUESTED"
    /\ resTarget[hoReceiver[r]] = r
    /\ holder'   = [holder   EXCEPT ![r] = hoReceiver[r]]
    /\ resState' = [resState EXCEPT ![hoReceiver[r]] = "GRANTED"]
    /\ UNCHANGED <<taskState, resTarget, taskCount, hoState, hoReceiver>>

\* Receiver confirms it now holds r; the handover completes.
CompleteHandover(r) ==
    /\ EnableHandover
    /\ hoState[r] = "IN_PROGRESS"
    /\ hoReceiver[r] /= "NONE"
    /\ holder[r] = hoReceiver[r]
    /\ resState[hoReceiver[r]] = "GRANTED"
    /\ hoState' = [hoState EXCEPT ![r] = "COMPLETED"]
    /\ UNCHANGED <<taskState, resState, resTarget, holder, taskCount, hoReceiver>>

\* Handover cleanup (COMPLETED -> NONE), freeing the handover slot for r.
CleanupHandover(r) ==
    /\ EnableHandover
    /\ hoState[r] = "COMPLETED"
    /\ hoState'    = [hoState    EXCEPT ![r] = "NONE"]
    /\ hoReceiver' = [hoReceiver EXCEPT ![r] = "NONE"]
    /\ UNCHANGED <<taskState, resState, resTarget, holder, taskCount>>

\* ─── Next-State Relation ────────────────────────────────────────────

\* Handover steps quantify over resources (and, for InitiateHandover, over the
\* sender and receiver machines). Kept in a separate disjunct for readability.
HandoverNext ==
    \E r \in Resources :
        \/ (\E s \in Machines : \E rcv \in Machines : InitiateHandover(s, r, rcv))
        \/ AckHandover(r)
        \/ BeginHandoverAtomic(r)
        \/ BeginHandoverNaive(r)
        \/ GrantToReceiver(r)
        \/ CompleteHandover(r)
        \/ CleanupHandover(r)

TaskNext ==
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

Next == TaskNext \/ HandoverNext

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
