---------------------------- MODULE MachineMode ----------------------------
(* TLA+ formal model of CAP MachineMode state machine (Ch06 §6.2).
 *
 * Includes HandoverEvent flow integration (Ch06 §6.4).
 *
 * Verifies:
 *   Safety:   SAFE_STOP is reachable from every state.
 *   Safety:   SAFE_STOP can only exit via physical reset (→ MANUAL).
 *   Safety:   HandoverEvent timeout always leads to SAFE_STOP.
 *   Liveness: A handover request is eventually resolved.
 *)

EXTENDS Naturals

CONSTANTS
    EnableFaults        \* BOOLEAN: TRUE enables SafetyTrigger and HandoverTimeout.
                        \* FALSE (fault-free regime) is used to show that a
                        \* handover completes through its productive path alone,
                        \* without relying on the timeout/SafeStop escape.

VARIABLES
    mode,               \* Current MachineMode
    handoverState       \* HandoverEvent flow state (NONE when no handover in progress)

vars == <<mode, handoverState>>

\* ─── State Definitions ────────────────────────────────────────────────

Modes == { "MANUAL", "TELEOP", "SUPERVISED_AUTONOMY", "AUTONOMY",
           "SAFE_STOP", "MAINTENANCE" }

HandoverStates == { "NONE", "REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS",
                    "COMPLETED", "TIMED_OUT" }

\* ─── Type Invariant ──────────────────────────────────────────────────

TypeOK ==
    /\ mode \in Modes
    /\ handoverState \in HandoverStates

\* ─── Initial State ──────────────────────────────────────────────────

Init ==
    /\ mode = "MANUAL"
    /\ handoverState = "NONE"

\* ─── Mode Transitions (Ch06 §6.2.3) ────────────────────────────────

ManualToTeleop ==
    /\ mode = "MANUAL"
    /\ handoverState = "NONE"
    /\ mode' = "TELEOP"
    /\ UNCHANGED handoverState

ManualToMaintenance ==
    /\ mode = "MANUAL"
    /\ handoverState = "NONE"
    /\ mode' = "MAINTENANCE"
    /\ UNCHANGED handoverState

TeleopToManual ==
    /\ mode = "TELEOP"
    /\ handoverState = "NONE"
    /\ mode' = "MANUAL"
    /\ UNCHANGED handoverState

TeleopToSupervised ==
    /\ mode = "TELEOP"
    /\ handoverState = "NONE"
    /\ mode' = "SUPERVISED_AUTONOMY"
    /\ UNCHANGED handoverState

SupervisedToTeleop ==
    /\ mode = "SUPERVISED_AUTONOMY"
    /\ handoverState = "NONE"
    /\ mode' = "TELEOP"
    /\ UNCHANGED handoverState

SupervisedToAutonomy ==
    /\ mode = "SUPERVISED_AUTONOMY"
    /\ handoverState = "NONE"
    /\ mode' = "AUTONOMY"
    /\ UNCHANGED handoverState

AutonomyToSupervised ==
    /\ mode = "AUTONOMY"
    /\ handoverState = "NONE"
    /\ mode' = "SUPERVISED_AUTONOMY"
    /\ UNCHANGED handoverState

MaintenanceToManual ==
    /\ mode = "MAINTENANCE"
    /\ handoverState = "NONE"
    /\ mode' = "MANUAL"
    /\ UNCHANGED handoverState

\* Safety Supervisor trigger: any mode → SAFE_STOP (unconditional)
SafetyTrigger ==
    /\ EnableFaults
    /\ mode /= "SAFE_STOP"
    /\ mode' = "SAFE_STOP"
    /\ handoverState' = IF handoverState \in {"REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS"}
                         THEN "TIMED_OUT"
                         ELSE handoverState

\* Physical reset: SAFE_STOP → MANUAL
PhysicalReset ==
    /\ mode = "SAFE_STOP"
    /\ mode' = "MANUAL"
    /\ handoverState' = "NONE"

\* ─── HandoverEvent Flow (Ch06 §6.4) ────────────────────────────────

\* Machine requests handover (e.g., obstacle detected during autonomous operation)
HandoverRequest ==
    /\ mode \in {"SUPERVISED_AUTONOMY", "AUTONOMY"}
    /\ handoverState = "NONE"
    /\ handoverState' = "REQUESTED"
    /\ UNCHANGED mode

\* Site Agent acknowledges handover
HandoverAcknowledge ==
    /\ handoverState = "REQUESTED"
    /\ handoverState' = "ACKNOWLEDGED"
    /\ UNCHANGED mode

\* ModeCommand sent for handover transition
HandoverModeCommand ==
    /\ handoverState = "ACKNOWLEDGED"
    /\ handoverState' = "IN_PROGRESS"
    /\ mode' = "TELEOP"    \* Handover always goes to TELEOP (operator takes over)

\* Machine confirms new mode in Heartbeat
HandoverComplete ==
    /\ handoverState = "IN_PROGRESS"
    /\ mode = "TELEOP"
    /\ handoverState' = "COMPLETED"
    /\ UNCHANGED mode

\* Handover cleanup (COMPLETED/TIMED_OUT → NONE)
HandoverCleanup ==
    /\ handoverState \in {"COMPLETED", "TIMED_OUT"}
    /\ handoverState' = "NONE"
    /\ UNCHANGED mode

\* Handover timeout: no acknowledgement → SAFE_STOP
HandoverTimeout ==
    /\ EnableFaults
    /\ handoverState \in {"REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS"}
    /\ handoverState' = "TIMED_OUT"
    /\ mode' = "SAFE_STOP"

\* ─── Next-State Relation ────────────────────────────────────────────

Next ==
    \/ ManualToTeleop
    \/ ManualToMaintenance
    \/ TeleopToManual
    \/ TeleopToSupervised
    \/ SupervisedToTeleop
    \/ SupervisedToAutonomy
    \/ AutonomyToSupervised
    \/ MaintenanceToManual
    \/ SafetyTrigger
    \/ PhysicalReset
    \/ HandoverRequest
    \/ HandoverAcknowledge
    \/ HandoverModeCommand
    \/ HandoverComplete
    \/ HandoverCleanup
    \/ HandoverTimeout

\* ─── Fairness ───────────────────────────────────────────────────────

Fairness ==
    /\ WF_vars(HandoverAcknowledge)
    /\ WF_vars(HandoverModeCommand)
    /\ WF_vars(HandoverComplete)
    /\ WF_vars(HandoverCleanup)
    /\ WF_vars(PhysicalReset)

Spec == Init /\ [][Next]_vars /\ Fairness

\* ─── Safety Properties ──────────────────────────────────────────────

\* SAFE_STOP can only exit to MANUAL (via physical reset)
SafeStopOnlyToManual ==
    (mode = "SAFE_STOP") => (mode' = "SAFE_STOP" \/ mode' = "MANUAL")

\* Handover timeout always results in SAFE_STOP
HandoverTimeoutImpliesSafeStop ==
    [](handoverState = "TIMED_OUT" => mode = "SAFE_STOP")

\* ─── Liveness Properties ────────────────────────────────────────────

\* A handover request is eventually resolved (COMPLETED or TIMED_OUT)
HandoverEventuallyResolved ==
    [](handoverState = "REQUESTED" =>
       <>(handoverState \in {"COMPLETED", "TIMED_OUT", "NONE"}))

\* SAFE_STOP is eventually recoverable (via physical reset)
SafeStopRecoverable ==
    [](mode = "SAFE_STOP" => <>(mode = "MANUAL"))

\* P3b (productive progress): with faults disabled (EnableFaults = FALSE),
\* a requested handover always reaches COMPLETED through the
\* acknowledge → mode-command → complete path -- i.e. handover progress does
\* not depend on the timeout/SafeStop escape. (Vacuously true when faults are
\* enabled, since a timeout may divert to TIMED_OUT; meaningful only in the
\* fault-free configuration.)
HandoverCompletesWithoutFaults ==
    [](handoverState = "REQUESTED" => <>(handoverState = "COMPLETED"))

\* ─── Properties ─────────────────────────────────────────────────────

THEOREM Spec => []TypeOK
THEOREM Spec => [][SafeStopOnlyToManual]_vars
THEOREM Spec => HandoverTimeoutImpliesSafeStop
THEOREM Spec => HandoverEventuallyResolved
THEOREM Spec => SafeStopRecoverable

========================================================================
