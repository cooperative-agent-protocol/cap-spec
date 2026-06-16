---------------------------- MODULE FencingInductive ----------------------------
(* Apalache (symbolic / SMT) INDUCTIVE-INVARIANT verification of the FENCING
 * property: under a monotonic per-resource grant epoch, at most one machine
 * actuates a resource even when a holder's release/expiry notification is lost
 * (a stale holder). The unbounded-by-induction counterpart of the
 * explicit-state ReservationFencing result.
 *
 * A machine "actuates" r iff it believes it holds r AND its fencing token equals
 * r's current grant epoch. The arbiter bumps the epoch on every grant, so a
 * stale holder's older token no longer matches and it cannot actuate.
 *
 * Set-valued encoding (a machine's belief and a resource's holder are sets of
 * size <= 1; empty = none/free) avoids mixing a sentinel with the uninterpreted
 * MACHINE / RESOURCE types. ExclusiveActuation (at most one actuator per
 * resource) is proved as an inductive invariant over symbolic sets:
 *   base:  Init    => IndInv          (apalache check --init=Init  --inv=IndInv --length=0)
 *   step:  IndInv /\ Next => IndInv'  (apalache check --init=IndInv --inv=IndInv --length=1)
 *)

EXTENDS Integers, FiniteSets, Apalache

CONSTANTS
    \* @type: Set(MACHINE);
    Machines,
    \* @type: Set(RESOURCE);
    Resources

MaxEpoch == 4

VARIABLES
    \* @type: RESOURCE -> Int;
    epoch,        \* current grant epoch per resource (monotonic)
    \* @type: RESOURCE -> Set(MACHINE);
    arbHolder,    \* arbiter's authoritative holder (>= 0, <= 1 machine); empty = free
    \* @type: MACHINE -> Set(RESOURCE);
    believes,     \* resource a machine believes it holds (<= 1); empty = none
    \* @type: MACHINE -> Int;
    token         \* the fencing token (epoch) a machine was granted

ConstInit ==
    /\ Machines = Gen(4)
    /\ Resources = Gen(4)

TypeOK ==
    /\ epoch \in [Resources -> 0..MaxEpoch]
    /\ arbHolder \in [Resources -> SUBSET Machines]
    /\ believes \in [Machines -> SUBSET Resources]
    /\ token \in [Machines -> 0..MaxEpoch]

Init ==
    /\ epoch = [r \in Resources |-> 0]
    /\ arbHolder = [r \in Resources |-> {}]
    /\ believes = [m \in Machines |-> {}]
    /\ token = [m \in Machines |-> 0]

Actuates(m, r) ==
    /\ r \in believes[m]
    /\ token[m] = epoch[r]

ExclusiveActuation ==
    \A r \in Resources :
        \A m1 \in Machines : \A m2 \in Machines :
            (Actuates(m1, r) /\ Actuates(m2, r)) => (m1 = m2)

\* Arbiter grants a free resource: bump the epoch (monotonic) and issue the token.
Grant(m, r) ==
    /\ arbHolder[r] = {}
    /\ believes[m] = {}
    /\ epoch[r] < MaxEpoch
    /\ epoch' = [epoch EXCEPT ![r] = epoch[r] + 1]
    /\ arbHolder' = [arbHolder EXCEPT ![r] = {m}]
    /\ believes' = [believes EXCEPT ![m] = {r}]
    /\ token' = [token EXCEPT ![m] = epoch[r] + 1]

\* Adversarial: arbiter reclaims r but the holder's notice is lost (belief kept).
ExpireLostNotify(r) ==
    /\ arbHolder[r] /= {}
    /\ arbHolder' = [arbHolder EXCEPT ![r] = {}]
    /\ UNCHANGED <<epoch, believes, token>>

\* A machine no longer recorded as the holder eventually drops its belief.
ClearStale(m) ==
    /\ \E r \in believes[m] : m \notin arbHolder[r]
    /\ believes' = [believes EXCEPT ![m] = {}]
    /\ UNCHANGED <<epoch, arbHolder, token>>

Next ==
    \/ \E m \in Machines : \E r \in Resources : Grant(m, r)
    \/ \E r \in Resources : ExpireLostNotify(r)
    \/ \E m \in Machines : ClearStale(m)

\* Supporting invariants that make ExclusiveActuation inductive:
\*  - beliefs and holders are singletons-or-empty,
\*  - a believing machine's token never exceeds the resource's epoch (so only the
\*    most recent grantee, whose token == epoch, can actuate).
Singletons ==
    /\ \A m \in Machines : Cardinality(believes[m]) <= 1
    /\ \A r \in Resources : Cardinality(arbHolder[r]) <= 1

EpochDominates ==
    \A m \in Machines : \A r \in Resources :
        (r \in believes[m]) => (token[m] <= epoch[r])

\* At most one machine has its token equal to a resource's current epoch.
UniqueCurrent ==
    \A r \in Resources :
        \A m1 \in Machines : \A m2 \in Machines :
            (token[m1] = epoch[r] /\ r \in believes[m1] /\
             token[m2] = epoch[r] /\ r \in believes[m2]) => (m1 = m2)

IndInv ==
    /\ TypeOK
    /\ Singletons
    /\ EpochDominates
    /\ ExclusiveActuation

================================================================================
