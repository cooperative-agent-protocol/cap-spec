---------------------------- MODULE SafetySupervisor ----------------------------
(* TLA+ component model: the independent Safety Supervisor (Layer C, ADR-003).
 *
 * CAP's central architectural claim is that safety is DECOUPLED from the LLM
 * and the coordination protocol: a deterministic Safety Supervisor can inhibit
 * a machine's actuation in ANY interleaving with the protocol/LLM layer, and
 * its inhibit has PRIORITY over any protocol authorization. In the existing
 * MachineMode model the supervisor is a single unconditional transition; here
 * it is modelled as an independent process that races the protocol, so the
 * decoupling becomes a checkable non-interference property.
 *
 *   SupervisorPriority = TRUE  : actuation is gated by the supervisor interlock
 *                                (a machine moves only while NOT inhibited) and
 *                                an inhibit forces an immediate, deterministic
 *                                stop -> InhibitStops HOLDS (the architecture
 *                                is correct: the protocol cannot move an
 *                                inhibited machine).
 *   SupervisorPriority = FALSE : the protocol authorization alone drives motion
 *                                and the supervisor cannot stop a moving machine
 *                                -> InhibitStops is VIOLATED, showing that the
 *                                decoupling REQUIRES the supervisor to have
 *                                priority + immediate-stop authority. The LLM/
 *                                protocol layer is deliberately unaware of the
 *                                safety channel (it may authorize while
 *                                inhibited), so safety cannot rest on the
 *                                protocol's cooperation.
 *)

EXTENDS Naturals

CONSTANTS
    Machines,           \* e.g., {"m1", "m2"}
    SupervisorPriority  \* BOOLEAN: TRUE = supervisor interlock has priority

VARIABLES
    authorized,         \* authorized[m]: protocol/LLM has authorized autonomous operation
    op,                 \* op[m] in {"STOPPED","MOVING"}: actual actuation state
    inhibit             \* inhibit[m]: supervisor inhibit active

vars == <<authorized, op, inhibit>>

TypeOK ==
    /\ authorized \in [Machines -> BOOLEAN]
    /\ op \in [Machines -> {"STOPPED", "MOVING"}]
    /\ inhibit \in [Machines -> BOOLEAN]

Init ==
    /\ authorized = [m \in Machines |-> FALSE]
    /\ op = [m \in Machines |-> "STOPPED"]
    /\ inhibit = [m \in Machines |-> FALSE]

\* ─── Protocol / LLM layer ────────────────────────────────────────────
\* The protocol authorizes autonomous operation. It does NOT consult the
\* supervisor -- that is the decoupling -- so authorization may be granted even
\* while the machine is inhibited (the LLM is unaware of the safety channel).
ProtocolAuthorize(m) ==
    /\ ~authorized[m]
    /\ authorized' = [authorized EXCEPT ![m] = TRUE]
    /\ UNCHANGED <<op, inhibit>>

ProtocolRevoke(m) ==
    /\ authorized[m]
    /\ authorized' = [authorized EXCEPT ![m] = FALSE]
    /\ op' = [op EXCEPT ![m] = "STOPPED"]
    /\ UNCHANGED inhibit

\* Machine begins actuating. Under SupervisorPriority this is gated by the
\* supervisor interlock (~inhibit); without priority the protocol authorization
\* alone suffices -- the unsafe design.
StartMove(m) ==
    /\ authorized[m]
    /\ op[m] = "STOPPED"
    /\ (SupervisorPriority => ~inhibit[m])
    /\ op' = [op EXCEPT ![m] = "MOVING"]
    /\ UNCHANGED <<authorized, inhibit>>

StopMove(m) ==
    /\ op[m] = "MOVING"
    /\ op' = [op EXCEPT ![m] = "STOPPED"]
    /\ UNCHANGED <<authorized, inhibit>>

\* ─── Safety Supervisor (independent, deterministic) ──────────────────
\* The supervisor asserts an inhibit (geofence breach, human detected, E-stop)
\* in any interleaving. Under priority it forces an immediate stop in the SAME
\* step, independent of the protocol's state. Without priority it cannot stop a
\* machine that is already moving.
SupervisorInhibit(m) ==
    /\ ~inhibit[m]
    /\ inhibit' = [inhibit EXCEPT ![m] = TRUE]
    /\ op' = IF SupervisorPriority THEN [op EXCEPT ![m] = "STOPPED"] ELSE op
    /\ UNCHANGED authorized

\* Physical reset clears the inhibit (operator action).
SupervisorReset(m) ==
    /\ inhibit[m]
    /\ inhibit' = [inhibit EXCEPT ![m] = FALSE]
    /\ UNCHANGED <<authorized, op>>

Next ==
    \E m \in Machines :
        \/ ProtocolAuthorize(m)
        \/ ProtocolRevoke(m)
        \/ StartMove(m)
        \/ StopMove(m)
        \/ SupervisorInhibit(m)
        \/ SupervisorReset(m)

Spec == Init /\ [][Next]_vars

\* ─── Safety: non-interference / supervisor priority ──────────────────
\* When the supervisor inhibits a machine, that machine is not actuating --
\* in EVERY interleaving with the protocol. This is the architecture's core
\* decoupling claim, expressed as a checkable invariant.
InhibitStops ==
    \A m \in Machines : inhibit[m] => (op[m] = "STOPPED")

THEOREM Spec => []TypeOK
THEOREM Spec => []InhibitStops   \* holds iff SupervisorPriority

================================================================================
