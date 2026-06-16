------------------------------ MODULE TimedHandover ------------------------------
(* TLA+ component model: BOUNDED-TIME handover resolution.
 *
 * The untimed models establish that a requested handover is *eventually*
 * resolved (HandoverEventuallyResolved). For a safety-relevant construction
 * protocol, "eventually safe-stops" is not a safety property --- "safe-stops
 * within a bounded time" is. This component adds a discrete clock and verifies
 * a bounded-response property: from a request, the handover reaches a resolved
 * state (Completed, or TimedOut -> SafeStop) within `Deadline` ticks.
 *
 * Discrete time is modelled explicitly (a `Tick` action advances `clock`); the
 * deadline guarantee is encoded the standard way --- when the deadline is
 * reached and the handover is still pending, `Tick` is disabled, so the only
 * enabled steps are resolution (Complete) or the deterministic Timeout. The
 * `Enforced` constant toggles that guarantee:
 *
 *   Enforced = TRUE  : the deadline is enforced (the deterministic supervisor /
 *                      timeout fires by `Deadline`) -> a pending handover never
 *                      ages past `Deadline`; BoundedResolution HOLDS.
 *   Enforced = FALSE : no deadline guarantee (time may pass without the timeout
 *                      firing) -> a pending handover ages past `Deadline`;
 *                      BoundedResolution is VIOLATED. This is the difference
 *                      between an unbounded "eventually" and a bounded-time
 *                      guarantee.
 *)

EXTENDS Naturals

CONSTANTS
    Deadline,   \* bound (in ticks) within which a handover must resolve
    Enforced    \* BOOLEAN: TRUE = the deadline is guaranteed to fire

VARIABLES
    hstate,     \* handover state
    clock,      \* ticks elapsed since the handover became pending (saturating)
    mode        \* "OPERATING" or "SAFESTOP"

vars == <<hstate, clock, mode>>

Pending == {"REQUESTED", "ACKNOWLEDGED", "IN_PROGRESS"}
HStates == Pending \cup {"NONE", "COMPLETED", "TIMED_OUT"}
MaxClock == Deadline + 1   \* one tick of headroom so a violation is representable

TypeOK ==
    /\ hstate \in HStates
    /\ clock \in 0..MaxClock
    /\ mode \in {"OPERATING", "SAFESTOP"}

Init ==
    /\ hstate = "NONE"
    /\ clock = 0
    /\ mode = "OPERATING"

\* ─── Bounded-response property ───────────────────────────────────────
\* A pending handover never ages beyond the deadline.
BoundedResolution ==
    (hstate \in Pending) => (clock <= Deadline)

\* ─── Handover progress ───────────────────────────────────────────────
Request ==
    /\ hstate = "NONE"
    /\ hstate' = "REQUESTED"
    /\ clock' = 0
    /\ UNCHANGED mode

Acknowledge ==
    /\ hstate = "REQUESTED"
    /\ hstate' = "ACKNOWLEDGED"
    /\ UNCHANGED <<clock, mode>>

Begin ==
    /\ hstate = "ACKNOWLEDGED"
    /\ hstate' = "IN_PROGRESS"
    /\ UNCHANGED <<clock, mode>>

Complete ==
    /\ hstate = "IN_PROGRESS"
    /\ hstate' = "COMPLETED"
    /\ UNCHANGED <<clock, mode>>

Cleanup ==
    /\ hstate \in {"COMPLETED", "TIMED_OUT"}
    /\ hstate' = "NONE"
    /\ clock' = 0
    /\ mode' = "OPERATING"

\* Time advances while a handover is pending. When Enforced, Tick is blocked once
\* the deadline is reached (forcing Timeout/Complete); when not Enforced, time may
\* pass past the deadline (the clock saturates at MaxClock).
Tick ==
    /\ hstate \in Pending
    /\ clock < MaxClock
    /\ (Enforced => clock < Deadline)
    /\ clock' = clock + 1
    /\ UNCHANGED <<hstate, mode>>

\* The deterministic timeout: a pending handover that has reached the deadline
\* times out and drives SafeStop.
Timeout ==
    /\ hstate \in Pending
    /\ clock >= Deadline
    /\ hstate' = "TIMED_OUT"
    /\ mode' = "SAFESTOP"
    /\ UNCHANGED clock

Next ==
    \/ Request \/ Acknowledge \/ Begin \/ Complete \/ Cleanup \/ Tick \/ Timeout

Spec == Init /\ [][Next]_vars

THEOREM Spec => []TypeOK
THEOREM Spec => []BoundedResolution   \* holds iff Enforced = TRUE

================================================================================
