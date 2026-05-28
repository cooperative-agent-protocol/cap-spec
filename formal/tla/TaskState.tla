---------------------------- MODULE TaskState ----------------------------
(* TLA+ formal model of CAP TaskState machine (Ch06 §6.1).
 *
 * Verifies:
 *   Safety:   Terminal states are absorbing (no exit once reached).
 *   Safety:   At most one task in RUNNING or BLOCKED at any time per machine.
 *   Liveness: Every task eventually reaches a terminal state.
 *
 * State × Event matrix from Ch06 §6.1.4 is encoded exactly.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS Tasks           \* Set of task IDs (e.g., {"t1", "t2"})

VARIABLES
    taskState,            \* taskState[t] ∈ States
    activeCount           \* number of tasks in RUNNING or BLOCKED

\* ─── State Definitions ────────────────────────────────────────────────

States == { "PENDING", "ACCEPTED", "RUNNING", "BLOCKED",
            "SUCCEEDED", "FAILED", "CANCELLED", "REJECTED", "EXPIRED" }

TerminalStates == { "SUCCEEDED", "FAILED", "CANCELLED", "REJECTED", "EXPIRED" }

ActiveStates == { "RUNNING", "BLOCKED" }

vars == <<taskState, activeCount>>

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ \A t \in Tasks : taskState[t] \in States
    /\ activeCount \in 0..Cardinality(Tasks)

\* ─── Safety Properties ──────────────────────────────────────────────

\* Terminal states are absorbing: once terminal, state never changes
TerminalAbsorbing ==
    \A t \in Tasks :
        taskState[t] \in TerminalStates =>
            taskState'[t] = taskState[t]

\* At most one task active (RUNNING or BLOCKED) at any time
AtMostOneActive ==
    activeCount <= 1

\* ─── Helper: count active tasks ─────────────────────────────────────

CountActive ==
    Cardinality({ t \in Tasks : taskState[t] \in ActiveStates })

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ taskState = [t \in Tasks |-> "PENDING"]
    /\ activeCount = 0

\* ─── Transitions (from Ch06 §6.1.3 & §6.1.4) ──────────────────────

\* PENDING → ACCEPTED (WorkOrderAck ACCEPTED)
Accept(t) ==
    /\ taskState[t] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![t] = "ACCEPTED"]
    /\ activeCount' = CountActive'

\* PENDING → REJECTED (WorkOrderAck REJECTED)
Reject(t) ==
    /\ taskState[t] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![t] = "REJECTED"]
    /\ activeCount' = CountActive'

\* PENDING → EXPIRED (response window elapsed)
Expire(t) ==
    /\ taskState[t] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![t] = "EXPIRED"]
    /\ activeCount' = CountActive'

\* PENDING → CANCELLED (CancelWorkOrder)
CancelPending(t) ==
    /\ taskState[t] = "PENDING"
    /\ taskState' = [taskState EXCEPT ![t] = "CANCELLED"]
    /\ activeCount' = CountActive'

\* ACCEPTED → RUNNING (ProgressEvent RUNNING)
\* Guard: at most one task may be in RUNNING or BLOCKED (Ch06 §6.6 rule 4)
StartRunning(t) ==
    /\ taskState[t] = "ACCEPTED"
    /\ activeCount = 0  \* no other task currently active
    /\ taskState' = [taskState EXCEPT ![t] = "RUNNING"]
    /\ activeCount' = CountActive'

\* ACCEPTED → CANCELLED (CancelWorkOrder)
CancelAccepted(t) ==
    /\ taskState[t] = "ACCEPTED"
    /\ taskState' = [taskState EXCEPT ![t] = "CANCELLED"]
    /\ activeCount' = CountActive'

\* RUNNING → BLOCKED (ProgressEvent BLOCKED)
Block(t) ==
    /\ taskState[t] = "RUNNING"
    /\ taskState' = [taskState EXCEPT ![t] = "BLOCKED"]
    /\ activeCount' = CountActive'

\* RUNNING → SUCCEEDED (ProgressEvent SUCCEEDED)
Succeed(t) ==
    /\ taskState[t] = "RUNNING"
    /\ taskState' = [taskState EXCEPT ![t] = "SUCCEEDED"]
    /\ activeCount' = CountActive'

\* RUNNING → FAILED (ProgressEvent FAILED)
FailRunning(t) ==
    /\ taskState[t] = "RUNNING"
    /\ taskState' = [taskState EXCEPT ![t] = "FAILED"]
    /\ activeCount' = CountActive'

\* RUNNING → CANCELLED (CancelWorkOrder)
CancelRunning(t) ==
    /\ taskState[t] = "RUNNING"
    /\ taskState' = [taskState EXCEPT ![t] = "CANCELLED"]
    /\ activeCount' = CountActive'

\* BLOCKED → RUNNING (blocking condition resolved)
Unblock(t) ==
    /\ taskState[t] = "BLOCKED"
    /\ taskState' = [taskState EXCEPT ![t] = "RUNNING"]
    /\ activeCount' = CountActive'

\* BLOCKED → FAILED (unrecoverable block)
FailBlocked(t) ==
    /\ taskState[t] = "BLOCKED"
    /\ taskState' = [taskState EXCEPT ![t] = "FAILED"]
    /\ activeCount' = CountActive'

\* BLOCKED → CANCELLED (CancelWorkOrder)
CancelBlocked(t) ==
    /\ taskState[t] = "BLOCKED"
    /\ taskState' = [taskState EXCEPT ![t] = "CANCELLED"]
    /\ activeCount' = CountActive'

\* ─── Next-State Relation ────────────────────────────────────────────

Next ==
    \E t \in Tasks :
        \/ Accept(t)
        \/ Reject(t)
        \/ Expire(t)
        \/ CancelPending(t)
        \/ StartRunning(t)
        \/ CancelAccepted(t)
        \/ Block(t)
        \/ Succeed(t)
        \/ FailRunning(t)
        \/ CancelRunning(t)
        \/ Unblock(t)
        \/ FailBlocked(t)
        \/ CancelBlocked(t)

\* ─── Fairness (for liveness) ────────────────────────────────────────

Fairness ==
    \A t \in Tasks :
        /\ WF_vars(Accept(t))
        /\ WF_vars(Reject(t))
        /\ WF_vars(Expire(t))
        /\ WF_vars(StartRunning(t))
        /\ SF_vars(Succeed(t))       \* Strong fairness: eventually completes
        /\ SF_vars(FailRunning(t))   \* Strong fairness: eventually fails if stuck
        /\ SF_vars(FailBlocked(t))   \* Strong fairness: blocked eventually resolves

Spec == Init /\ [][Next]_vars /\ Fairness

\* ─── Liveness ───────────────────────────────────────────────────────

\* Every task eventually reaches a terminal state
EventuallyTerminal ==
    \A t \in Tasks : <>(taskState[t] \in TerminalStates)

\* ─── Properties to check ────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => []AtMostOneActive
THEOREM Spec => EventuallyTerminal

========================================================================
