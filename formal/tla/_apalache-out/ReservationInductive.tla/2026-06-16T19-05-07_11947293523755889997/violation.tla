---------------------------- MODULE counterexample ----------------------------

EXTENDS ReservationInductive

(* Constant initialization state *)
ConstInit ==
  Machines = { "FRESH10_OF_MACHINE", "FRESH9_OF_MACHINE" }
    /\ Resources = {"FRESH13_OF_RESOURCE"}

(* Initial state [_transition(0)] *)
State0 ==
  Machines = { "FRESH10_OF_MACHINE", "FRESH9_OF_MACHINE" }
    /\ Resources = {"FRESH13_OF_RESOURCE"}
    /\ held
      = SetAsFun({ <<"FRESH10_OF_MACHINE", {}>>, <<"FRESH9_OF_MACHINE", {}>> })

(* State1 [_transition(0)] *)
State1 ==
  Machines = { "FRESH10_OF_MACHINE", "FRESH9_OF_MACHINE" }
    /\ Resources = {"FRESH13_OF_RESOURCE"}
    /\ held
      = SetAsFun({ <<"FRESH122_OF_MACHINE", {"FRESH125_OF_RESOURCE"}>>,
        <<"FRESH130_OF_MACHINE", {}>> })

(* The following formula holds true in the last state and violates the invariant *)
InvariantViolation == Skolem((\E m_5 \in Machines: ~(held[m_5] = {})))

================================================================================
(* Created by Apalache on Tue Jun 16 19:05:10 JST 2026 *)
(* https://github.com/apalache-mc/apalache *)
