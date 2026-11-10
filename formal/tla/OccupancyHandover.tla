--------------------------- MODULE OccupancyHandover ---------------------------
(* Ownership and occupancy of a shared conflict zone (a carrier loading bay)
 * under a FAMILY of coordination schemes, with an untrusted client.
 *
 * Why this model exists. The other component models reason about logical
 * ownership only: who holds a reservation, and whether a stale token may act.
 * A physical zone differs from a data object in one respect that matters here:
 * the zone cannot reject a stale holder. A machine whose lease expired, or
 * whose token was fenced, may still be standing in the bay. This module couples
 * three things in one state machine:
 *   (1) the arbiter's logical state (holder, generation, custody, queue, plan),
 *   (2) each machine's physical presence in the conflict zone (pos),
 *   (3) each machine's local view of its authority (auth, authLive) and the
 *       real-time validity of time-limited entry permits (valid),
 * and checks scheme-neutral safety properties S1-S3 and the additional
 * guarantees G1-G2 for every member of a family of schemes.
 *
 * The client (an LLM planner or any other software) is UNTRUSTED: it may issue
 * any request at any time - a request, a premature release, a hand-over to any
 * machine, or a motion command into the zone. Only the arbiter's rules and the
 * machine's entry gate decide what takes effect.
 *
 * Scheme family (CONSTANTS):
 *   Arb        "none"   optimistic grants (no exclusivity)
 *              "deny"   grant only when the zone is not held (deny-on-busy)
 *              "queue"  as "deny", and only to the head of a FIFO of requesters
 *   Gate       "none"   the machine enters whenever commanded
 *              "local"  the machine enters if it remembers being granted
 *              "permit" the machine enters only with a live, single-use,
 *                       time-limited entry permit issued by the arbiter
 *   Release    "onDone"   a release frees the zone at once
 *              "onVacate" the releaser stays in custody until its vacancy is
 *                         confirmed
 *   Expiry     "none"      a holder that stops renewing keeps the zone
 *              "ttl"       a holder that stops renewing loses the zone once its
 *                          permits are no longer counted
 *              "ttlVacate" as "ttl", and the expired holder stays in custody
 *                          until its vacancy is confirmed
 *   Succession "free"       any eligible requester may be granted next
 *              "designated" only the successor designated by the plan; a
 *                           release with a designated successor is routed as
 *                           an atomic hand-over
 *
 * Assumptions (CONSTANTS, TRUE = assumed to hold):
 *   SensorSound (A2) a vacancy is confirmed only for a machine that is out
 *   TimingSound (A4) a machine's local view of a permit lapses before the
 *                    permit's real validity ends, and the arbiter stops
 *                    counting a permit only after its real validity ends.
 *                    This is the lease lemma: the machine times a permit from
 *                    the moment it SENT the request, for T(1-rho) on its
 *                    monotonic clock; the arbiter counts it for T(1+rho) on its
 *                    own clock from the grant.
 *   AuthOK      (A5) a client can only speak for its own machine
 * A1 (entry only through the gate) is structural: Enter is the only action
 * that moves a machine into the zone.
 *
 * Environment: machine crash, recovery and link loss (Faults); arbiter crash
 * and restart with its state kept (Restart = "durable") or lost ("lossy");
 * BootScoped decides whether permits carry the arbiter's boot id. After a lossy
 * restart a scheme that times its authority waits until every earlier permit
 * has lapsed (the usual lease grace period), and a scheme that tracks
 * occupancy also waits until every machine is confirmed out.
 *)
EXTENDS Naturals, FiniteSets, Sequences, TLC

CONSTANTS
    Machines,       \* carriers contending for the zone, e.g. {"c1", "c2", "c3"}
    Incompatible,   \* set of 2-element sets {a, b}: a and b must not be in the zone together
    Arb, Gate, Release, Expiry, Succession,
    SensorSound, TimingSound, AuthOK,
    Faults,         \* BOOLEAN: machine crash/recovery, link loss, message loss
    Restart,        \* "none" | "durable" | "lossy"
    BootScoped,     \* BOOLEAN: permits carry the arbiter's boot id
    MaxGen,         \* bound on grant generations (finiteness)
    MaxBoot         \* bound on arbiter restarts (finiteness)

None == "none"

ASSUME Arb \in {"none", "deny", "queue"}
ASSUME Gate \in {"none", "local", "permit"}
ASSUME Release \in {"onDone", "onVacate"}
ASSUME Expiry \in {"none", "ttl", "ttlVacate"}
ASSUME Succession \in {"free", "designated"}
ASSUME Restart \in {"none", "durable", "lossy"}
ASSUME \A pr \in Incompatible : pr \subseteq Machines /\ Cardinality(pr) = 2

Boots   == 0..MaxBoot
Gens    == 0..MaxGen
\* k is a ghost field (history only, never read by a guard): the index of the
\* grant event the authorisation belongs to.
MaxK    == MaxGen * (MaxBoot + 1)
Permits == [m : Machines, b : Boots, g : Gens, k : 0..MaxK]

\* Every pair of carriers is incompatible in the loading bay (the default
\* compatibility relation; the loader itself is not modelled as a contender).
AllCarrierPairs == {pr \in SUBSET Machines : Cardinality(pr) = 2}
Symm == Permutations(Machines)

OccAware == Release = "onVacate" \/ Expiry = "ttlVacate"   \* tracks occupancy (custody)
Leased   == Gate = "permit" \/ Expiry \in {"ttl", "ttlVacate"} \* times authority

VARIABLES
    pos,        \* pos[m] \in {"out", "in"}: physical presence in the conflict zone
    alive,      \* alive[m]: the machine (and its agent) is running
    conn,       \* conn[m]: its link to the arbiter is up
    knownBoot,  \* knownBoot[m]: the arbiter boot id m learned at its last (re)connection
    auth,       \* auth[m] \subseteq Permits, at most one element: the authorisation m holds ({} = none)
    authLive,   \* authLive[m]: m's own view that auth[m] is still usable
    wants,      \* wants[m]: the arbiter has a pending request for m
    arbUp,      \* the arbiter is running
    boot,       \* the arbiter's boot counter
    gen,        \* generation of the current grant
    holder,     \* holder \in Machines \cup {None}: logical holder of the zone
    custody,    \* machines the arbiter still treats as possibly inside (other than the holder)
    queue,      \* FIFO of requesters (Arb = "queue")
    planned,    \* successor designated by the plan for the next turnover, or None
    guard,      \* "open" | "waitTime" | "waitVacancy": arbiter's restart guard
    live,       \* permits the arbiter still counts as possibly in use
    valid,      \* permits still within their real-time validity
    inflight,   \* authorisation messages sent but not yet received
    nGrants,    \* history: number of grant/transfer events so far
    curTok,     \* history: [m, k] of the latest grant/transfer event
    violS3,     \* history: some machine entered with authority superseded by a later grant
    violG2,     \* history: someone other than the planned successor was given the zone
    lastIn,     \* history: the machine that entered most recently
    nDistinct   \* history: entries by a machine other than the previous entrant (capped at 2)

mvars == <<pos, alive, conn, knownBoot, auth, authLive, wants>>
avars == <<arbUp, boot, gen, holder, custody, queue, planned, guard, live>>
xvars == <<valid, inflight>>
hvars == <<nGrants, curTok, violS3, violG2, lastIn, nDistinct>>
obs   == <<violS3, violG2, lastIn, nDistinct>>   \* history not touched by TransferTo
vars  == <<mvars, avars, xvars, hvars>>

TypeOK ==
    /\ pos \in [Machines -> {"out", "in"}]
    /\ alive \in [Machines -> BOOLEAN]
    /\ conn \in [Machines -> BOOLEAN]
    /\ knownBoot \in [Machines -> Boots]
    /\ auth \in [Machines -> SUBSET Permits]
    /\ \A m \in Machines : Cardinality(auth[m]) <= 1
    /\ authLive \in [Machines -> BOOLEAN]
    /\ wants \in [Machines -> BOOLEAN]
    /\ arbUp \in BOOLEAN
    /\ boot \in Boots
    /\ gen \in Gens
    /\ holder \in Machines \cup {None}
    /\ custody \subseteq Machines
    /\ planned \in Machines \cup {None}
    /\ guard \in {"open", "waitTime", "waitVacancy"}
    /\ live \subseteq Permits
    /\ valid \subseteq Permits
    /\ inflight \subseteq Permits
    /\ nGrants \in 0..MaxK
    /\ curTok \in [m : Machines \cup {None}, k : 0..MaxK]
    /\ violS3 \in BOOLEAN /\ violG2 \in BOOLEAN
    /\ lastIn \in Machines \cup {None}
    /\ nDistinct \in 0..2

Init ==
    /\ pos = [m \in Machines |-> "out"]
    /\ alive = [m \in Machines |-> TRUE]
    /\ conn = [m \in Machines |-> TRUE]
    /\ knownBoot = [m \in Machines |-> 0]
    /\ auth = [m \in Machines |-> {}]
    /\ authLive = [m \in Machines |-> FALSE]
    /\ wants = [m \in Machines |-> FALSE]
    /\ arbUp = TRUE /\ boot = 0 /\ gen = 0
    /\ holder = None /\ custody = {} /\ queue = <<>> /\ planned = None
    /\ guard = "open" /\ live = {} /\ valid = {} /\ inflight = {}
    /\ nGrants = 0 /\ curTok = [m |-> None, k |-> 0]
    /\ violS3 = FALSE /\ violG2 = FALSE /\ lastIn = None /\ nDistinct = 0

\* ---------------------------------------------------------------- helpers
Inc(a, b) == {a, b} \in Incompatible
InQueue(m) == \E i \in 1..Len(queue) : queue[i] = m
Dequeue(m) == SelectSeq(queue, LAMBDA x : x /= m)
NoIncCustody(m) == \A c \in custody : ~Inc(m, c)
NoIncLive(m) == \A p \in live : p.m = m \/ ~Inc(m, p.m)
PBoot == IF BootScoped THEN boot ELSE 0     \* boot id carried by new permits
NewPermit(m, g, k) == [m |-> m, b |-> PBoot, g |-> g, k |-> k]
HasInflight(m) == \E p \in inflight : p.m = m
\* A designated successor exists and the scheme honours it.
Routed == Succession = "designated" /\ Arb /= "none" /\ planned /= None

\* An authorisation message to m: a grant notice (Gate "local") or a permit
\* (Gate "permit", also counted by the arbiter and valid in real time).
SendAuth(m, g, k) ==
    LET p == NewPermit(m, g, k) IN
    /\ inflight' = inflight \cup {p}
    /\ IF Gate = "permit"
          THEN /\ live' = live \cup {p}
               /\ valid' = valid \cup {p}
          ELSE UNCHANGED <<live, valid>>

\* Atomic transfer of the zone from the current holder s to the planned
\* successor; s stays in custody when the scheme tracks occupancy.
TransferTo(s, keepInCustody) ==
    /\ gen < MaxGen
    /\ holder' = planned
    /\ custody' = (custody \cup (IF keepInCustody THEN {s} ELSE {})) \ {planned}
    /\ gen' = gen + 1
    /\ queue' = Dequeue(planned)
    /\ wants' = [wants EXCEPT ![planned] = FALSE]
    /\ planned' = None
    /\ nGrants' = nGrants + 1
    /\ curTok' = [m |-> planned, k |-> nGrants + 1]

\* ---------------------------------------------------------------- arbiter
Grantable(m) ==
    /\ arbUp /\ guard = "open"
    /\ wants[m] /\ alive[m] /\ conn[m]
    /\ gen < MaxGen
    /\ IF Arb = "none" THEN TRUE
       ELSE /\ holder = None
            /\ Arb = "queue" => (queue /= <<>> /\ Head(queue) = m)
            /\ NoIncCustody(m)
            /\ NoIncLive(m)
            /\ (Succession = "designated" /\ planned /= None) => m = planned
    /\ ~HasInflight(m)

Grant(m) ==
    /\ Grantable(m)
    /\ holder' = m
    /\ gen' = gen + 1
    /\ custody' = custody \ {m}
    /\ queue' = Dequeue(m)
    /\ wants' = [wants EXCEPT ![m] = FALSE]
    /\ planned' = None
    /\ violG2' = (violG2 \/ (planned /= None /\ m /= planned))
    /\ nGrants' = nGrants + 1
    /\ curTok' = [m |-> m, k |-> nGrants + 1]
    /\ IF Gate = "none" THEN UNCHANGED <<inflight, live, valid>>
                        ELSE SendAuth(m, gen + 1, nGrants + 1)
    /\ UNCHANGED <<pos, alive, conn, knownBoot, auth, authLive,
                   arbUp, boot, guard, violS3, lastIn, nDistinct>>

\* The holder obtains a fresh authorisation (after a hand-over, or to re-enter).
IssueAuth(m) ==
    /\ Arb /= "none" /\ Gate /= "none"
    /\ arbUp /\ guard = "open"
    /\ holder = m /\ alive[m] /\ conn[m]
    /\ NoIncCustody(m) /\ NoIncLive(m)
    /\ ~HasInflight(m)
    /\ SendAuth(m, gen, curTok.k)
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, custody, queue, planned,
                   guard, hvars>>

\* The plan (the Site's deterministic coordinator) designates the next machine.
Plan(x) ==
    /\ arbUp /\ planned = None /\ holder /= None /\ x /= holder /\ wants[x]
    /\ Arb = "queue" => (queue /= <<>> /\ Head(queue) = x)
    /\ planned' = x
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, custody, queue, guard,
                   live, xvars, hvars>>

LeaseExpire(m) ==
    /\ Expiry \in {"ttl", "ttlVacate"}
    /\ arbUp /\ holder = m /\ (~alive[m] \/ ~conn[m])   \* renewals have stopped
    /\ \A p \in live : p.m /= m                          \* none of m's permits is counted
    /\ IF Routed     \* at the generation bound the transfer is disabled, not degraded
          THEN TransferTo(m, Expiry = "ttlVacate")
          ELSE /\ holder' = None
               /\ custody' = IF Expiry = "ttlVacate" THEN custody \cup {m} ELSE custody
               /\ UNCHANGED <<gen, queue, wants, planned, nGrants, curTok>>
    /\ UNCHANGED <<pos, alive, conn, knownBoot, auth, authLive, arbUp, boot,
                   guard, live, xvars, obs>>

ConfirmVacant(m) ==
    /\ arbUp /\ m \in custody
    /\ SensorSound => pos[m] = "out"
    /\ custody' = custody \ {m}
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, queue, planned, guard, live,
                   xvars, hvars>>

\* The arbiter stops counting a permit (its own conservative timer ran out).
ArbLapse(p) ==
    /\ p \in live
    /\ TimingSound => p \notin valid
    /\ live' = live \ {p}
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, custody, queue, planned,
                   guard, xvars, hvars>>

\* ---------------------------------------------------------------- time and messages
\* A permit's real-time validity ends. With TimingSound the machine's own view
\* has already lapsed (its timer started earlier and runs short).
RealLapse(p) ==
    /\ p \in valid
    /\ TimingSound => ~(p \in auth[p.m] /\ authLive[p.m])
    /\ valid' = valid \ {p}
    /\ UNCHANGED <<mvars, avars, inflight, hvars>>

LocalLapse(m) ==
    /\ Gate = "permit" /\ auth[m] /= {} /\ authLive[m]
    /\ authLive' = [authLive EXCEPT ![m] = FALSE]
    /\ UNCHANGED <<pos, alive, conn, knownBoot, auth, wants, avars, xvars, hvars>>

Receive(p) ==
    /\ p \in inflight /\ alive[p.m] /\ conn[p.m]
    /\ inflight' = inflight \ {p}
    /\ IF BootScoped /\ p.b /= knownBoot[p.m]
          THEN UNCHANGED <<auth, authLive>>                 \* from an earlier arbiter boot: dropped
          ELSE /\ auth' = [auth EXCEPT ![p.m] = {p}]
               /\ authLive' = [authLive EXCEPT ![p.m] =
                                 IF Gate = "permit" THEN (~TimingSound \/ p \in valid) ELSE TRUE]
    /\ UNCHANGED <<pos, alive, conn, knownBoot, wants, avars, valid, hvars>>

DropMsg(p) ==
    /\ Faults /\ p \in inflight
    /\ inflight' = inflight \ {p}
    /\ UNCHANGED <<mvars, avars, valid, hvars>>

\* ---------------------------------------------------------------- machines
\* A1: the only way into the zone, through the machine's entry gate.
GateOpen(m) ==
    CASE Gate = "none"   -> TRUE
      [] Gate = "local"  -> auth[m] /= {}
      [] Gate = "permit" -> /\ auth[m] /= {} /\ authLive[m]
                            /\ BootScoped => \A q \in auth[m] : q.b = knownBoot[m]

\* m's entry is authorised when it uses the authorisation of the latest grant,
\* and that grant was to m (with no gate: when the latest grant was to m).
Authorised(m) ==
    /\ curTok.m = m
    /\ Gate /= "none" => \E p \in auth[m] : p.k = curTok.k

Enter(m) ==
    /\ pos[m] = "out" /\ alive[m] /\ GateOpen(m)
    /\ pos' = [pos EXCEPT ![m] = "in"]
    /\ violS3' = (violS3 \/ ~Authorised(m))
    /\ IF Gate = "permit"                                   \* single use
          THEN /\ auth' = [auth EXCEPT ![m] = {}]
               /\ authLive' = [authLive EXCEPT ![m] = FALSE]
          ELSE UNCHANGED <<auth, authLive>>
    /\ lastIn' = m
    /\ nDistinct' = IF lastIn /= m /\ nDistinct < 2 THEN nDistinct + 1 ELSE nDistinct
    /\ UNCHANGED <<alive, conn, knownBoot, wants, avars, xvars, violG2, nGrants, curTok>>

Exit(m) ==
    /\ pos[m] = "in" /\ alive[m]
    /\ pos' = [pos EXCEPT ![m] = "out"]
    /\ UNCHANGED <<alive, conn, knownBoot, auth, authLive, wants, avars, xvars, hvars>>

\* ---------------------------------------------------------------- untrusted client
\* Client c speaks for machine m; without A5 it may speak for any machine.
Speaks(c, m) == (AuthOK => c = m) /\ alive[c] /\ conn[c] /\ arbUp

Req(c, m) ==
    /\ Speaks(c, m) /\ ~wants[m] /\ holder /= m
    /\ wants' = [wants EXCEPT ![m] = TRUE]
    /\ queue' = IF Arb = "queue" /\ ~InQueue(m) THEN Append(queue, m) ELSE queue
    /\ UNCHANGED <<pos, alive, conn, knownBoot, auth, authLive, arbUp, boot, gen,
                   holder, custody, planned, guard, live, xvars, hvars>>

\* When m's own agent gives the zone up (release or hand-over), it forgets its
\* authorisation and voids any permit for that reservation still in flight: a
\* permit that arrives after the release is discarded on arrival. (Found by
\* model checking: without this, a late permit lets the releaser back in.)
\* A release forged for m by another client (~AuthOK) does none of this.
OwnGiveUp(c, m) ==
    IF c = m
       THEN /\ auth' = [auth EXCEPT ![m] = {}]
            /\ authLive' = [authLive EXCEPT ![m] = FALSE]
            /\ inflight' = {p \in inflight : p.m /= m}
       ELSE UNCHANGED <<auth, authLive, inflight>>

\* A release for m, at any time (also before m has left the zone).
Rel(c, m) ==
    /\ Speaks(c, m) /\ holder = m /\ guard = "open"
    /\ IF Routed     \* at the generation bound the transfer is disabled, not degraded
          THEN TransferTo(m, OccAware)
          ELSE /\ holder' = None
               /\ custody' = IF Release = "onVacate" THEN custody \cup {m} ELSE custody
               /\ UNCHANGED <<gen, queue, wants, planned, nGrants, curTok>>
    /\ OwnGiveUp(c, m)
    /\ UNCHANGED <<pos, alive, conn, knownBoot, arbUp, boot, guard, live, valid, obs>>

\* A hand-over request from holder s to x; honoured only for the planned successor.
HandoverReq(c, s, x) ==
    /\ Speaks(c, s) /\ Succession = "designated" /\ Arb /= "none"
    /\ holder = s /\ guard = "open" /\ planned = x /\ x /= s /\ gen < MaxGen
    /\ TransferTo(s, OccAware)
    /\ OwnGiveUp(c, s)
    /\ UNCHANGED <<pos, alive, conn, knownBoot, arbUp, boot, guard,
                   live, valid, obs>>

\* ---------------------------------------------------------------- faults
Crash(m) ==
    /\ Faults /\ alive[m]
    /\ alive' = [alive EXCEPT ![m] = FALSE]
    /\ auth' = [auth EXCEPT ![m] = {}]                      \* a reboot forgets permits
    /\ authLive' = [authLive EXCEPT ![m] = FALSE]
    /\ UNCHANGED <<pos, conn, knownBoot, wants, avars, xvars, hvars>>

Recover(m) ==
    /\ Faults /\ ~alive[m] /\ arbUp
    /\ alive' = [alive EXCEPT ![m] = TRUE]
    /\ conn' = [conn EXCEPT ![m] = TRUE]
    /\ knownBoot' = [knownBoot EXCEPT ![m] = boot]
    /\ UNCHANGED <<pos, auth, authLive, wants, avars, xvars, hvars>>

Disconnect(m) ==
    /\ Faults /\ alive[m] /\ conn[m]
    /\ conn' = [conn EXCEPT ![m] = FALSE]
    /\ UNCHANGED <<pos, alive, knownBoot, auth, authLive, wants, avars, xvars, hvars>>

Reconnect(m) ==
    /\ alive[m] /\ ~conn[m] /\ arbUp
    /\ conn' = [conn EXCEPT ![m] = TRUE]
    /\ knownBoot' = [knownBoot EXCEPT ![m] = boot]
    /\ UNCHANGED <<pos, alive, auth, authLive, wants, avars, xvars, hvars>>

\* E1: a crashed machine is towed out of the zone (liveness only).
Remove(m) ==
    /\ Faults /\ ~alive[m] /\ pos[m] = "in"
    /\ pos' = [pos EXCEPT ![m] = "out"]
    /\ UNCHANGED <<alive, conn, knownBoot, auth, authLive, wants, avars, xvars, hvars>>

ArbCrash ==
    /\ Restart /= "none" /\ arbUp /\ boot < MaxBoot
    /\ arbUp' = FALSE
    /\ conn' = [m \in Machines |-> FALSE]                     \* every stream breaks
    /\ UNCHANGED <<pos, alive, knownBoot, auth, authLive, wants, boot, gen, holder,
                   custody, queue, planned, guard, live, xvars, hvars>>

ArbRestart ==
    /\ ~arbUp
    /\ arbUp' = TRUE
    /\ boot' = boot + 1
    /\ IF Restart = "durable"
          THEN /\ guard' = "open"
               /\ UNCHANGED <<gen, holder, custody, queue, planned, live, wants>>
          ELSE /\ holder' = None /\ custody' = {} /\ queue' = <<>> /\ planned' = None
               /\ live' = {} /\ gen' = 0
               /\ wants' = [m \in Machines |-> FALSE]
               /\ guard' = IF Leased THEN "waitTime"
                           ELSE IF OccAware THEN "waitVacancy" ELSE "open"
    /\ UNCHANGED <<pos, alive, conn, knownBoot, auth, authLive, xvars, hvars>>

\* The grace period after a lossy restart: with TimingSound it ends only after
\* every earlier permit's real validity has ended.
GraceOver ==
    /\ arbUp /\ guard = "waitTime"
    /\ TimingSound => valid = {}
    /\ guard' = IF OccAware THEN "waitVacancy" ELSE "open"
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, custody, queue, planned, live,
                   xvars, hvars>>

ConfirmAllVacant ==
    /\ arbUp /\ guard = "waitVacancy"
    /\ SensorSound => \A m \in Machines : pos[m] = "out"
    /\ guard' = "open"
    /\ UNCHANGED <<mvars, arbUp, boot, gen, holder, custody, queue, planned, live,
                   xvars, hvars>>

\* ---------------------------------------------------------------- spec
Next ==
    \/ \E m \in Machines : Grant(m) \/ IssueAuth(m) \/ Plan(m) \/ LeaseExpire(m)
                           \/ ConfirmVacant(m) \/ LocalLapse(m)
                           \/ Enter(m) \/ Exit(m)
                           \/ Crash(m) \/ Recover(m) \/ Disconnect(m) \/ Reconnect(m)
                           \/ Remove(m)
    \/ \E p \in live : ArbLapse(p)
    \/ \E p \in valid : RealLapse(p)
    \/ \E p \in inflight : Receive(p) \/ DropMsg(p)
    \/ \E c, m \in Machines : Req(c, m) \/ Rel(c, m)
    \/ \E c, s, x \in Machines : HandoverReq(c, s, x)
    \/ ArbCrash \/ ArbRestart \/ GraceOver \/ ConfirmAllVacant

Spec == Init /\ [][Next]_vars

\* ---------------------------------------------------------------- properties
\* S1: two incompatible machines are never in the zone together.
S1 == \A a, b \in Machines : Inc(a, b) => ~(pos[a] = "in" /\ pos[b] = "in")
\* S2: while the arbiter can grant, it accounts for every machine in the zone.
S2 == (arbUp /\ guard = "open") =>
        \A m \in Machines : pos[m] = "in" => (m = holder \/ m \in custody)
\* S3: no machine enters the zone without being its holder.
S3 == ~violS3
\* G1: once a successor is planned, the zone is never unheld until it is handed on.
G1 == planned /= None => holder /= None
\* G2: no machine other than the planned successor is given the zone.
G2 == ~violG2
\* Non-triviality: two successive entries by different machines are reachable
\* (expected to be VIOLATED in a fault-free run; a scheme that never lets a
\* second machine in is trivially safe and is reported as such).
NotCycle == nDistinct < 2

Safety == S1 /\ S2 /\ S3

\* ---------------------------------------------------------------- liveness (G4)
\* G4: a holder that has crashed eventually recovers or loses the zone, so the zone can come back to the others.
\* Checked under LiveSpec: the arbiter's own steps and the passage of time are weakly fair, and a crashed machine is
\* eventually towed out (E1); its recovery is NOT fair (it may never come back).
\* (Below the generation bound only: at the bound a hand-over is disabled by the model's finiteness, not by the scheme.)
G4 == \A m \in Machines : (holder = m /\ ~alive[m] /\ gen < MaxGen) ~> (holder /= m \/ alive[m])

LiveSpec ==
    /\ Spec
    /\ WF_vars(\E m \in Machines : LeaseExpire(m))
    /\ WF_vars(\E m \in Machines : ConfirmVacant(m))
    /\ WF_vars(\E m \in Machines : Remove(m))
    /\ WF_vars(\E m \in Machines : LocalLapse(m))
    /\ WF_vars(\E p \in valid : RealLapse(p))
    /\ WF_vars(\E p \in live : ArbLapse(p))
    /\ WF_vars(GraceOver \/ ConfirmAllVacant)
================================================================================
