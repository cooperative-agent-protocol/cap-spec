----------------------------- MODULE ZoneTable -----------------------------
(* How an entry gate comes to know a conflict zone, and what the arbiter must wait for (assumption A1 of
 * OccupancyHandover, which takes the gates' knowledge of the zone for granted).
 *
 * The arbiter keeps a table of zones with a version. It sends the table to the machines over ordered streams; a
 * machine reports with every heartbeat which table its gate enforces. A restart of a machine empties its gate and
 * begins a new stream. A restart of the arbiter begins a new start; an authorisation of the old start may still be
 * usable then. With its journal the arbiter takes its zones up again; without it the table of the new start is
 * empty until the coordinator registers the zones again.
 *
 *   Rule "ack" (the protocol):
 *       - a gate without a table lets its machine make no move;
 *       - the arbiter authorises a machine for the zone only when every other machine has reported a table of this
 *         start that holds the zone as it stands;
 *       - after a restart without its journal the arbiter sends no table until every authorisation of the earlier
 *         start has lapsed (the wait of T(1 + rho) it keeps anyway).
 *   Rule "noack" (broken):    the arbiter authorises without waiting for the reports.
 *   Rule "failopen" (broken): a gate without a table lets its machine move.
 *   Rule "nohold" (broken):   a restarted arbiter sends its (still empty) table at once.
 *
 * Safe: while a machine holds an authorisation for the zone, no other machine's gate would let its machine into it
 * unchecked. TLC confirms Safe for "ack" and finds a counterexample for each broken rule; NeverAuthorised is
 * violated for "ack", so Safe does not hold vacuously.
 *
 * Assumed here: a zone is not moved while an authorisation for it is out (SetZone), and a stream delivers in order.
 *)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS
    Machines,   \* the carriers (the loader, to which the zone is open, is not gated by it)
    MaxVer,     \* table versions per start
    MaxBoot,    \* starts of the arbiter
    MaxGeo,     \* geometries the zone can take (1 .. MaxGeo; 0: no zone)
    MaxQ,       \* messages in a stream at once
    Rule

ASSUME Rule \in {"ack", "noack", "failopen", "nohold"}

None  == [b |-> 0, v |-> 0, z |-> 0]      \* a gate without a table (b = 0)
NoTag == [b |-> 0, v |-> 0]

VARIABLES
    boot,       \* the arbiter's start, 1 .. MaxBoot
    ver,        \* the version of its table in this start
    zone,       \* the zone's geometry in its table (0: not registered)
    since,      \* the version at which the zone was set as it stands
    acked,      \* acked[m]: the version the arbiter has on record for m's gate in this start (-1: none)
    gate,       \* gate[m] = [b, v, z]: start and version of its table, the zone it lists
    hold,       \* the arbiter withholds its table (after a restart without its journal)
    down,       \* down[m]: tables on their way to m, in order
    up,         \* up[m]: m's heartbeats on their way to the arbiter, in order
    auth,       \* auth[m]: the geometry m holds a usable authorisation for (0: none)
    authBoot    \* authBoot[m]: the start that issued it

vars == <<boot, ver, zone, since, acked, gate, hold, down, up, auth, authBoot>>

Enforces(m, g) == gate[m].b # 0 /\ gate[m].z = g
\* the gate of k would let its machine into a zone of geometry g without asking
LetsIn(k, g)   == IF gate[k].b = 0 THEN Rule = "failopen" ELSE ~Enforces(k, g)

Init ==
    /\ boot = 1 /\ ver = 0 /\ zone = 0 /\ since = 0
    /\ acked = [m \in Machines |-> -1]
    /\ gate = [m \in Machines |-> None]
    /\ hold = FALSE
    /\ down = [m \in Machines |-> <<>>]
    /\ up = [m \in Machines |-> <<>>]
    /\ auth = [m \in Machines |-> 0]
    /\ authBoot = [m \in Machines |-> 0]

\* the coordinator registers the zone, or moves it - not while an authorisation for another geometry is out
SetZone(g) ==
    /\ g # zone /\ ver < MaxVer
    /\ \A m \in Machines : auth[m] \in {0, g}
    /\ zone' = g /\ ver' = ver + 1 /\ since' = ver + 1
    /\ UNCHANGED <<boot, acked, gate, hold, down, up, auth, authBoot>>

Push(m) ==
    /\ ~hold
    /\ Len(down[m]) < MaxQ
    /\ down' = [down EXCEPT ![m] = Append(@, [b |-> boot, v |-> ver, z |-> zone])]
    /\ UNCHANGED <<boot, ver, zone, since, acked, gate, hold, up, auth, authBoot>>

\* a later table of the same start, or the table of a later start, replaces the gate's; an earlier one is dropped
Recv(m) ==
    /\ down[m] # <<>>
    /\ LET t == Head(down[m]) g == gate[m] IN
       gate' = [gate EXCEPT ![m] =
           IF t.b < g.b \/ (t.b = g.b /\ t.v < g.v) THEN g ELSE [b |-> t.b, v |-> t.v, z |-> t.z]]
    /\ down' = [down EXCEPT ![m] = Tail(@)]
    /\ UNCHANGED <<boot, ver, zone, since, acked, hold, up, auth, authBoot>>

\* the wait after a restart without the journal is over: every authorisation of an earlier start has lapsed
Unhold ==
    /\ hold
    /\ \A k \in Machines : auth[k] # 0 => authBoot[k] = boot
    /\ hold' = FALSE
    /\ UNCHANGED <<boot, ver, zone, since, acked, gate, down, up, auth, authBoot>>

Heartbeat(m) ==
    /\ Len(up[m]) < MaxQ
    /\ up' = [up EXCEPT ![m] = Append(@, IF gate[m].b = 0 THEN NoTag ELSE [b |-> gate[m].b, v |-> gate[m].v])]
    /\ UNCHANGED <<boot, ver, zone, since, acked, gate, hold, down, auth, authBoot>>

RecvHeartbeat(m) ==
    /\ up[m] # <<>>
    /\ LET t == Head(up[m]) IN
       acked' = [acked EXCEPT ![m] = IF t.b = boot /\ t.v <= ver THEN t.v ELSE -1]
    /\ up' = [up EXCEPT ![m] = Tail(@)]
    /\ UNCHANGED <<boot, ver, zone, since, gate, hold, down, auth, authBoot>>

Authorise(m) ==
    /\ zone # 0 /\ auth[m] = 0
    /\ Rule # "noack" => \A k \in Machines \ {m} : acked[k] >= since
    /\ auth' = [auth EXCEPT ![m] = zone]
    /\ authBoot' = [authBoot EXCEPT ![m] = boot]
    /\ UNCHANGED <<boot, ver, zone, since, acked, gate, hold, down, up>>

Lapse(m) ==
    /\ auth[m] # 0
    /\ auth' = [auth EXCEPT ![m] = 0]
    /\ UNCHANGED <<boot, ver, zone, since, acked, gate, hold, down, up, authBoot>>

\* a machine's agent restarts: an empty gate, a new stream, no authorisation (A4)
MachineRestart(m) ==
    /\ gate' = [gate EXCEPT ![m] = None]
    /\ down' = [down EXCEPT ![m] = <<>>]
    /\ up' = [up EXCEPT ![m] = <<>>]
    /\ auth' = [auth EXCEPT ![m] = 0]
    /\ UNCHANGED <<boot, ver, zone, since, acked, hold, authBoot>>

\* the arbiter restarts: a new start, no record of the gates; the streams go on. With the journal it takes its zones
\* up again; without it the table is empty and withheld
ArbRestart ==
    /\ boot < MaxBoot
    /\ boot' = boot + 1 /\ ver' = 0 /\ since' = 0
    /\ acked' = [m \in Machines |-> -1]
    /\ \/ zone' = zone /\ hold' = FALSE
       \/ zone' = 0 /\ hold' = (Rule # "nohold")
    /\ UNCHANGED <<gate, down, up, auth, authBoot>>

Next ==
    \/ \E g \in 1 .. MaxGeo : SetZone(g)
    \/ \E m \in Machines : Push(m) \/ Recv(m) \/ Heartbeat(m) \/ RecvHeartbeat(m)
                           \/ Authorise(m) \/ Lapse(m) \/ MachineRestart(m)
    \/ ArbRestart \/ Unhold

Spec == Init /\ [][Next]_vars

Safe == \A m \in Machines : auth[m] # 0 => \A k \in Machines \ {m} : ~LetsIn(k, auth[m])

\* violated on purpose: an authorisation is reachable under the protocol's rule
NeverAuthorised == \A m \in Machines : auth[m] = 0
=============================================================================
