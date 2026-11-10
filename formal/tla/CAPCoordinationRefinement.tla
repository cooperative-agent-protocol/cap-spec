------------------------ MODULE CAPCoordinationRefinement ------------------------
(* Refinement mappings from CAPCoordination to the simplified models whose invariants are proved inductive
 * (reviewer R2-1: "explicitly map the structurally simplified inductive models to CAPCoordination and demonstrate
 * that the abstraction preserves relevant transitions").
 *
 *   RA: ReservationAbstract with  held[m]       <- {resTarget[m]} if resState[m] = "GRANTED" else {}
 *   HA: HandoverAbstract    with  granted[m]    <- the same
 *                                 requested[m]  <- {resTarget[m]} if resState[m] = "REQUESTED" else {}
 *                                 hoState       <- hoState
 *                                 receiverOf[r] <- {hoReceiver[r]} if hoReceiver[r] /= "NONE" else {}
 *
 * TLC checks PROPERTY RefinesReservation and RefinesHandover: every step of CAPCoordination maps to a step of the
 * abstract Next or to a stutter. Task-only steps stutter; RequestResource/RetryReservation map to Request,
 * DenyResource to Deny, GrantResource to Acquire, CompleteTask to Release(Plain), BeginHandoverAtomic to Transfer
 * (RA) and BeginHandoverAtomic (HA). Without Transfer in RA and Deny in HA the check fails at exactly those steps
 * (refinement_*_without.cfg) - the gap R2-1 suspected.
 *)
EXTENDS CAPCoordination

CONSTANTS AllowTransfer, AllowDeny   \* TRUE: the abstractions as extended; FALSE: as they were

GrantedSet(m)   == IF resState[m] = "GRANTED"   THEN {resTarget[m]} ELSE {}
RequestedSet(m) == IF resState[m] = "REQUESTED" THEN {resTarget[m]} ELSE {}

RA == INSTANCE ReservationAbstract WITH held <- [m \in Machines |-> GrantedSet(m)]

HA == INSTANCE HandoverAbstract WITH
        granted    <- [m \in Machines |-> GrantedSet(m)],
        requested  <- [m \in Machines |-> RequestedSet(m)],
        hoState    <- hoState,
        receiverOf <- [r \in Resources |-> IF hoReceiver[r] = "NONE" THEN {} ELSE {hoReceiver[r]}]

RefinesReservation == RA!Spec
RefinesHandover    == HA!Spec
================================================================================
