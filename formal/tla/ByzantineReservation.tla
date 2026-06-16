--------------------------- MODULE ByzantineReservation ---------------------------
(* TLA+ component model: reservation exclusivity under a BYZANTINE (lying)
 * machine, and the trusted-arbiter design that contains it.
 *
 * Every other CAP model assumes agents follow the protocol --- they prove the
 * protocol correct in exactly the scenario where it is not needed. CAP's
 * architecture, however, rests on the opposite assumption: machine agents (and
 * the LLMs that drive them) are UNTRUSTED, and the Site Agent's reservation
 * arbiter (and the Safety Supervisor) are the trusted enforcement points. This
 * component formalises that trust model: a machine may LIE --- assert that it
 * holds a resource it was never granted --- and we check whether exclusive
 * actuation still holds.
 *
 *   TrustedArbiter = TRUE  : a machine actuates a resource only if the arbiter's
 *                            authoritative holder map recognises it as the
 *                            holder; a machine's self-asserted claim carries no
 *                            authority. A lie cannot create a second actuator,
 *                            so NoTwoActuators HOLDS.
 *   TrustedArbiter = FALSE : the system honours a machine's self-asserted hold
 *                            (no authoritative arbiter check). A lying machine
 *                            and the arbiter's true grantee both actuate the
 *                            same resource -> NoTwoActuators is VIOLATED.
 *
 * The verified statement is the architecture's premise: exclusivity is an
 * invariant of the *arbiter*, not of the agents' good behaviour.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Machines,        \* e.g., {"m1", "m2"}  (any machine may lie)
    Resources,       \* e.g., {"LP-1"}
    TrustedArbiter   \* BOOLEAN: TRUE = actuation is gated by the arbiter's holder map

NoMachine == "NONE"
NoResource == "NONE"

VARIABLES
    arbHolder,       \* arbHolder[r] in Machines \cup {NoMachine}: arbiter's authoritative grant
    claim            \* claim[m]    in Resources \cup {NoResource}: resource m asserts it holds

vars == <<arbHolder, claim>>

TypeOK ==
    /\ arbHolder \in [Resources -> Machines \cup {NoMachine}]
    /\ claim \in [Machines -> Resources \cup {NoResource}]

Init ==
    /\ arbHolder = [r \in Resources |-> NoMachine]
    /\ claim = [m \in Machines |-> NoResource]

\* A machine "actuates" r when it asserts holding r and --- under a trusted
\* arbiter --- the arbiter's authoritative map agrees. Under an untrusted
\* arbiter, the self-asserted claim alone drives actuation.
ActsAsHolder(m, r) ==
    /\ claim[m] = r
    /\ (TrustedArbiter => arbHolder[r] = m)

\* Safety: at most one machine actuates a given resource.
NoTwoActuators ==
    \A r \in Resources :
        Cardinality({ m \in Machines : ActsAsHolder(m, r) }) <= 1

\* The arbiter's authoritative map is always single-holder (it is the source of
\* truth); this holds regardless of TrustedArbiter and regardless of lies.
ArbiterExclusive ==
    \A r \in Resources :
        Cardinality({ m \in Machines : arbHolder[r] = m }) <= 1

\* ─── Honest arbiter path ─────────────────────────────────────────────
\* The arbiter grants a free resource to a machine; the (honest) machine then
\* claims exactly what it was granted.
Grant(m, r) ==
    /\ arbHolder[r] = NoMachine
    /\ claim[m] = NoResource
    /\ arbHolder' = [arbHolder EXCEPT ![r] = m]
    /\ claim' = [claim EXCEPT ![m] = r]

Release(m, r) ==
    /\ arbHolder[r] = m
    /\ claim[m] = r
    /\ arbHolder' = [arbHolder EXCEPT ![r] = NoMachine]
    /\ claim' = [claim EXCEPT ![m] = NoResource]

\* ─── Byzantine action ────────────────────────────────────────────────
\* Any machine may LIE: assert that it holds r without an arbiter grant (the
\* arbiter's authoritative map is unchanged). Models a compromised/buggy machine
\* agent (or a misbehaving LLM) that ignores the protocol.
ByzantineClaim(m, r) ==
    /\ claim[m] = NoResource
    /\ arbHolder[r] /= m
    /\ claim' = [claim EXCEPT ![m] = r]
    /\ UNCHANGED arbHolder

\* A lying machine eventually drops the false claim (recovery / supervisor reset).
DropClaim(m) ==
    /\ claim[m] /= NoResource
    /\ arbHolder[claim[m]] /= m
    /\ claim' = [claim EXCEPT ![m] = NoResource]
    /\ UNCHANGED arbHolder

Next ==
    \/ \E m \in Machines, r \in Resources : Grant(m, r)
    \/ \E m \in Machines, r \in Resources : Release(m, r)
    \/ \E m \in Machines, r \in Resources : ByzantineClaim(m, r)
    \/ \E m \in Machines : DropClaim(m)

Spec == Init /\ [][Next]_vars

THEOREM Spec => []TypeOK
THEOREM Spec => []ArbiterExclusive
THEOREM Spec => []NoTwoActuators   \* holds iff TrustedArbiter = TRUE

================================================================================
