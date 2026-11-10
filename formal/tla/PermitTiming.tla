----------------------------- MODULE PermitTiming -----------------------------
(* The lease lemma for entry permits (assumption A4 of OccupancyHandover), with drifting clocks and message delay.
 *
 * One machine asks the arbiter for an entry permit of validity T. Real time advances in ticks of K units; in each
 * tick the machine's and the arbiter's monotonic clocks each advance by any amount in K-D .. K+D (relative rate
 * error at most rho = D/K). The request and the grant are delayed by any number of ticks.
 *
 *   Rule "send" (the protocol): the machine times the permit from the moment it SENT the request and treats it as
 *       usable while its clock has advanced less than T(1-rho) since then; the arbiter counts the permit from the
 *       grant until its own clock has advanced T(1+rho).
 *   Rule "receive" (broken): the machine times the permit from the moment it RECEIVED the grant.
 *   Rule "nodrift" (broken): both sides use T without the (1 -/+ rho) factors.
 *
 * Lemma (Contained): whenever the machine treats the permit as usable, the arbiter still counts it.
 * Proof sketch for "send": if the machine's clock advanced less than T(1-rho) since the send, less than T of real
 * time has passed since the send, hence since the (later) grant; in less than T of real time the arbiter's clock
 * advances less than T(1+rho). TLC confirms Contained for "send" and finds counterexamples for the two broken rules.
 *
 * Entry margin: the machine starts a crossing only with at least Delta(1+rho) left on its clock, and a crossing
 * takes at most Delta of real time; CrossingCovered states that a crossing always ends while the arbiter still
 * counts the permit.
 *)
EXTENDS Integers

CONSTANTS
    K,          \* real-time units per tick
    D,          \* maximal clock deviation per tick (rho = D / K)
    T,          \* permit validity, in clock units (a multiple of K)
    Delta,      \* bound on the real time of a crossing, in real-time units (a multiple of K)
    MaxTicks,   \* horizon (finiteness)
    Rule        \* "send" | "receive" | "nodrift"

ASSUME K > 0 /\ D >= 0 /\ D < K /\ T % K = 0 /\ Delta % K = 0
ASSUME Rule \in {"send", "receive", "nodrift"}

VARIABLES
    tick,       \* number of real ticks elapsed
    cm, ca,     \* machine and arbiter clock readings
    phase,      \* "idle" | "requested" | "granted" | "received"
    cmSend,     \* machine clock at the send
    cmRecv,     \* machine clock at the receipt
    caGrant,    \* arbiter clock at the grant
    crossing,   \* 0 = no crossing under way; else real-time units of the crossing left
    crossedLate \* history: a crossing ended after the arbiter stopped counting the permit

vars == <<tick, cm, ca, phase, cmSend, cmRecv, caGrant, crossing, crossedLate>>

\* thresholds, exact in integers: T(1-rho) = T(K-D)/K and T(1+rho) = T(K+D)/K
MachineLife == IF Rule = "nodrift" THEN T ELSE (T * (K - D)) \div K
ArbiterLife == IF Rule = "nodrift" THEN T ELSE (T * (K + D)) \div K
EntryMargin == IF Rule = "nodrift" THEN Delta ELSE (Delta * (K + D)) \div K

MachineStart == IF Rule = "receive" THEN cmRecv ELSE cmSend
Usable  == phase = "received" /\ cm - MachineStart < MachineLife
Counted == phase \in {"granted", "received"} /\ ca - caGrant < ArbiterLife

Init ==
    /\ tick = 0 /\ cm = 0 /\ ca = 0 /\ phase = "idle"
    /\ cmSend = 0 /\ cmRecv = 0 /\ caGrant = 0 /\ crossing = 0 /\ crossedLate = FALSE

Send ==
    /\ phase = "idle"
    /\ phase' = "requested" /\ cmSend' = cm
    /\ UNCHANGED <<tick, cm, ca, cmRecv, caGrant, crossing, crossedLate>>

Grant ==
    /\ phase = "requested"
    /\ phase' = "granted" /\ caGrant' = ca
    /\ UNCHANGED <<tick, cm, ca, cmSend, cmRecv, crossing, crossedLate>>

Receive ==
    /\ phase = "granted"
    /\ phase' = "received" /\ cmRecv' = cm
    /\ UNCHANGED <<tick, cm, ca, cmSend, caGrant, crossing, crossedLate>>

\* The gate lets a crossing start only with the entry margin left.
StartCrossing ==
    /\ phase = "received" /\ crossing = 0 /\ Delta > 0
    /\ MachineLife - (cm - MachineStart) >= EntryMargin
    /\ crossing' = Delta
    /\ UNCHANGED <<tick, cm, ca, phase, cmSend, cmRecv, caGrant, crossedLate>>

\* One tick of real time: both clocks drift independently; a crossing under way progresses and may end.
Tick ==
    /\ tick < MaxTicks
    /\ tick' = tick + 1
    /\ \E dm \in (K - D)..(K + D) : cm' = cm + dm
    /\ \E da \in (K - D)..(K + D) : ca' = ca + da
    /\ IF crossing > 0
          THEN /\ crossing' = crossing - K
               \* the crossing ends at the end of this tick: is the permit still counted then?
               /\ crossedLate' = (crossedLate \/ (crossing - K = 0 /\ ~(ca' - caGrant < ArbiterLife)))
          ELSE UNCHANGED <<crossing, crossedLate>>
    /\ UNCHANGED <<phase, cmSend, cmRecv, caGrant>>

Next == Send \/ Grant \/ Receive \/ StartCrossing \/ Tick

Spec == Init /\ [][Next]_vars

\* The lease lemma.
Contained == Usable => Counted
\* A crossing admitted by the gate ends while the arbiter still counts the permit.
CrossingCovered == ~crossedLate
================================================================================
