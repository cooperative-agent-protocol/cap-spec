#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 CAP Authors
"""S1 and S2 for ANY number of machines, zones and permits: an inductive invariant, checked with an SMT solver.

The model checker (../tla/OccupancyHandover.tla with TLC) explores the occupancy model for two and three machines.
This script proves the two physical safety properties without a bound: for any set of machines, any set of zones,
any set of permit identifiers and, in each zone, any symmetric and irreflexive incompatibility relation.

  S1  two machines that are incompatible in a zone are never in that zone together
  S2  while the arbiter's guard is open, every machine in a zone is the zone's holder or in its custody
  S3  a permit that a machine's gate can still use is one the arbiter still counts (or, after a restart that lost
      the journal, is waiting out)

How. The scheme is written as a transition system over uninterpreted sorts (machines M, zones Z, permit
identifiers I) whose state is a handful of relations - who is inside which zone, which permits a machine's gate can
still use, which are on their way, which the arbiter counts, which are valid in real time, who holds a zone, who is
in its custody - and the arbiter's restart guard. An invariant Inv (ten universally quantified conjuncts, S1 to S3 among them) is shown inductive:

  Init => Inv,        and for every action A:   Inv /\\ A => Inv'

Each of these is one formula of the Bernays-Schoenfinkel class (exists-forall, no function symbols), which is
decidable; Z3 answers "unsat" for the negation of each. Nothing is bounded.

What the transition system is. It is an abstraction of OccupancyHandover for the schemes with an arbiter, a permit
gate and custody (Arb /= "none", Gate = "permit", Release = "onVacate", Expiry in {"none", "ttlVacate"}, either
succession), with sound sensing (A2), sound permit timing (A4), the grace wait after a restart that lost the journal,
and custody that ends only when no permit of the machine is counted. It has MORE behaviours than that model: it does
not look at who asked, who is planned, whether a machine or the arbiter is up, or who sent a release - so a release
or a hand-over made in another machine's name (no authentication, A5) and one made by the Site's coordinator are
steps of it. Every step of the model is one step of this system or a short sequence of them (the table in
RESULTS.md); what holds in every state reachable here holds in every state reachable there.

The script also removes one rule at a time and reports that the invariant is then no longer inductive (the solver
finds a state and a step): the custody rule, the vacancy sensing, the two conditions of a permit, the two halves of
the timing lemma, the grace wait, and the gate. That is a check of the encoding, not a proof that the weaker scheme
is unsafe - the model checker's counterexamples are that.

  python3 occupancy_inductive.py            # needs z3 on the PATH (https://github.com/Z3Prover/z3)
  python3 occupancy_inductive.py --dump DIR # also write the SMT-LIB files
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# relation -> sorts of its arguments
REL = {"pos": "MZ", "usable": "MZI", "inflight": "MZI", "live": "MZI", "valid": "MZI", "custody": "MZ", "hold": "MZ"}


def decls() -> str:
    out = ["(set-logic UF)", "(declare-sort M 0)", "(declare-sort Z 0)", "(declare-sort I 0)",
           "(declare-datatypes ((G 0)) (((open) (waitTime) (waitVacancy))))",
           "(declare-fun Inc (M M Z) Bool)",
           "(assert (forall ((a M) (z Z)) (not (Inc a a z))))",
           "(assert (forall ((a M) (b M) (z Z)) (=> (Inc a b z) (Inc b a z))))"]
    for s in ("", "2"):
        for r, sorts in REL.items():
            out.append(f"(declare-fun {r}{s} ({' '.join(sorts)}) Bool)")
        out.append(f"(declare-const guard{s} G)")
    return "\n".join(out)


def inv(s: str) -> dict[str, str]:
    """The invariant's conjuncts over the state with suffix ``s`` ("" before the step, "2" after)."""
    g = f"guard{s}"

    def potw(m: str, i: str) -> str:      # permit i can still let m into z: valid, and with m's gate or on its way
        return f"(and (valid{s} {m} z {i}) (or (usable{s} {m} z {i}) (inflight{s} {m} z {i})))"

    def acc(m: str) -> str:               # the arbiter accounts for m in z
        return f"(or (hold{s} {m} z) (custody{s} {m} z))"

    return {
        "H1 one holder": f"(forall ((a M) (b M) (z Z)) (=> (and (hold{s} a z) (hold{s} b z)) (= a b)))",
        "I1 a usable permit is valid": f"(forall ((m M) (z Z) (i I)) (=> (usable{s} m z i) (valid{s} m z i)))",
        "I2 a valid permit is counted": f"(=> (not (= {g} waitTime)) "
                                        f"(forall ((m M) (z Z) (i I)) (=> (valid{s} m z i) (live{s} m z i))))",
        "S2 inside => holder or custody": f"(=> (= {g} open) (forall ((m M) (z Z)) (=> (pos{s} m z) {acc('m')})))",
        "I4 may enter => holder or custody": f"(=> (= {g} open) "
                                             f"(forall ((m M) (z Z) (i I)) (=> {potw('m', 'i')} {acc('m')})))",
        "I6 exclusive authority": f"(forall ((a M) (b M) (z Z) (i I) (j I)) "
                                  f"(not (and (Inc a b z) {potw('a', 'i')} {potw('b', 'j')})))",
        "I7 may enter => the others are out": f"(forall ((m M) (b M) (z Z) (i I)) "
                                              f"(=> (and {potw('m', 'i')} (Inc m b z)) (not (pos{s} b z))))",
        "I8 no permit valid while waiting for vacancy": f"(=> (= {g} waitVacancy) "
                                                        f"(forall ((m M) (z Z) (i I)) (not (valid{s} m z i))))",
        "S1 no two incompatible machines inside": f"(forall ((a M) (b M) (z Z)) "
                                                  f"(=> (Inc a b z) (not (and (pos{s} a z) (pos{s} b z)))))",
        "S3 a permit in use is one the arbiter makes room for": f"(forall ((m M) (z Z) (i I)) (=> (usable{s} m z i) "
                                                                f"(or (live{s} m z i) (= {g} waitTime))))",
    }


NO_INC_CUSTODY = "(forall ((c M)) (=> (custody c z0) (not (Inc m0 c z0))))"
NO_INC_LIVE = "(forall ((b M) (j I)) (=> (live b z0 j) (not (Inc m0 b z0))))"
AT = "(and (= x m0) (= w z0))"                    # the machine and the zone of the step (relations over M, Z)
THE = "(and (= x m0) (= w z0) (= y i0))"          # ... and the permit (relations over M, Z, I)


def actions(mut: str = "") -> dict[str, dict]:
    """name -> params (constants), guard (conjuncts), upd (relation -> definition over x, w[, y]), guard2.
    ``mut`` removes one rule (see MUTATIONS and IMPLIED)."""
    a: dict[str, dict] = {}
    a["Issue(m, z, i): a permit for the holder"] = dict(
        params="MZI", guard=["(= guard open)", "(hold m0 z0)"]
        + ([] if mut == "permit while an incompatible machine is in custody" else [NO_INC_CUSTODY])
        + ([] if mut in ("permit while an incompatible machine's permit is counted",
                         "no counted-permit condition at all") else [NO_INC_LIVE]),
        upd={r: f"(or ({r} x w y) {THE})" for r in ("inflight", "live", "valid")})
    a["Hold(m, z): the free zone is granted"] = dict(
        params="MZ", guard=["(= guard open)", "(forall ((x M)) (not (hold x z0)))"]
        + ([] if mut == "grant while an incompatible machine is in custody" else [NO_INC_CUSTODY])
        + ([] if mut in ("grant while an incompatible machine's permit is counted",
                         "no counted-permit condition at all") else [NO_INC_LIVE]),
        upd={"hold": "(or (and (hold x w) (not (= w z0))) (and (= x m0) (= w z0)))",
             "custody": f"(and (custody x w) (not {AT}))"})
    a["Transfer(s, x, z): hand-over, the sender into custody"] = dict(
        params="MMZ", guard=["(hold m0 z0)", "(not (= m0 m1))"],
        upd={"hold": "(or (and (hold x w) (not (= w z0))) (and (= x m1) (= w z0)))",
             "custody": "(or (and (custody x w) (not (and (= x m1) (= w z0)))) (and (= x m0) (= w z0)))"})
    a["Release(s, z): given up, by anyone, into custody"] = dict(
        params="MZ", guard=["(hold m0 z0)"],
        upd={"hold": "(and (hold x w) (not (= w z0)))", "custody": f"(or (custody x w) {AT})"})
    a["Vacate(m, z): out of custody"] = dict(
        params="MZ", guard=["(custody m0 z0)"]
        + ([] if mut == "vacancy confirmed without sensing (A2)" else ["(not (pos m0 z0))"])
        + ([] if mut == "custody ends while a permit of the machine is counted"
           else ["(forall ((j I)) (not (live m0 z0 j)))"]),
        upd={"custody": f"(and (custody x w) (not {AT}))"})
    a["ArbLapse(m, z, i): the arbiter stops counting a permit"] = dict(
        params="MZI", guard=["(live m0 z0 i0)"]
        + ([] if mut == "the arbiter stops counting a valid permit (A4)" else ["(not (valid m0 z0 i0))"]),
        upd={"live": f"(and (live x w y) (not {THE}))"})
    a["RealLapse(m, z, i): a permit's validity ends"] = dict(
        params="MZI", guard=["(valid m0 z0 i0)"]
        + ([] if mut == "the machine's view outlasts the validity (A4)" else ["(not (usable m0 z0 i0))"]),
        upd={"valid": f"(and (valid x w y) (not {THE}))"})
    a["Receive(m, z, i): a permit arrives"] = dict(
        params="MZI", guard=["(inflight m0 z0 i0)"],
        upd={"inflight": f"(and (inflight x w y) (not {THE}))",
             "usable": f"(or (usable x w y) (and {THE} (valid m0 z0 i0)))"})
    a["Lose(m, z, i): a permit in flight is lost or voided"] = dict(
        params="MZI", guard=["(inflight m0 z0 i0)"], upd={"inflight": f"(and (inflight x w y) (not {THE}))"})
    a["Forget(m, z, i): the gate drops a permit"] = dict(
        params="MZI", guard=["(usable m0 z0 i0)"], upd={"usable": f"(and (usable x w y) (not {THE}))"})
    a["Enter(m, z, i): through the gate, the permit used up"] = dict(
        params="MZI", guard=["(not (pos m0 z0))"]
        + ([] if mut == "entry without a permit (A1)" else ["(usable m0 z0 i0)"]),
        upd={"pos": f"(or (pos x w) {AT})", "usable": f"(and (usable x w y) (not {THE}))"})
    a["Exit(m, z)"] = dict(params="MZ", guard=["(pos m0 z0)"], upd={"pos": f"(and (pos x w) (not {AT}))"})
    a["Restart: the arbiter restarts without its journal"] = dict(
        params="", guard=[], upd={"hold": "false", "custody": "false", "live": "false"},
        guard2="open" if mut == "no grace wait after a lost journal" else "waitTime")
    a["GraceOver: every earlier permit has lapsed"] = dict(
        params="", guard=["(= guard waitTime)", "(forall ((m M) (z Z) (i I)) (not (valid m z i)))"],
        guard2="waitVacancy")
    a["AllVacant: every machine is seen out of every zone"] = dict(
        params="", guard=["(= guard waitVacancy)", "(forall ((m M) (z Z)) (not (pos m z)))"], guard2="open")
    return a


# rules without which the invariant is not inductive
MUTATIONS = ["custody ends while a permit of the machine is counted", "vacancy confirmed without sensing (A2)",
             "permit while an incompatible machine is in custody",
             "the arbiter stops counting a valid permit (A4)", "the machine's view outlasts the validity (A4)",
             "no grace wait after a lost journal", "entry without a permit (A1)"]
# conditions the arbiter also checks, which the other rules already imply (the invariant stays inductive without them)
IMPLIED = ["permit while an incompatible machine's permit is counted",
           "grant while an incompatible machine's permit is counted", "no counted-permit condition at all",
           "grant while an incompatible machine is in custody"]


def step(act: dict) -> str:
    out = []
    names = {"M": ["m0", "m1"], "Z": ["z0"], "I": ["i0"]}
    seen = {"M": 0, "Z": 0, "I": 0}
    for sort in act["params"]:
        out.append(f"(declare-const {names[sort][seen[sort]]} {sort})")
        seen[sort] += 1
    out += [f"(assert {g})" for g in act["guard"]]
    for r, sorts in REL.items():
        bound = " ".join(f"({'xwy'[k]} {srt})" for k, srt in enumerate(sorts))
        args = " ".join("xwy"[k] for k in range(len(sorts)))
        body = act.get("upd", {}).get(r, f"({r} {args})")
        out.append(f"(assert (forall ({bound}) (= ({r}2 {args}) {body})))")
    out.append(f"(assert (= guard2 {act.get('guard2', 'guard')}))")
    return "\n".join(out)


def solve(text: str, z3: str, dump: Path | None, name: str) -> str:
    with tempfile.NamedTemporaryFile("w", suffix=".smt2", delete=False) as fh:
        fh.write(text)
        path = Path(fh.name)
    if dump is not None:
        shutil.copyfile(path, dump / (name + ".smt2"))
    res = subprocess.run([z3, "-smt2", "-T:120", str(path)], capture_output=True, text=True).stdout.strip()
    path.unlink()
    return res.splitlines()[0] if res else "no answer"


def check(mut: str, z3: str, dump: Path | None) -> tuple[int, list[str]]:
    """The proof obligations with rule ``mut`` removed ("" for none). Returns (#obligations, the ones not proved)."""
    pre = "\n".join(f"(assert {f})" for f in inv("").values())
    post = inv("2")
    n, open_ = 0, []
    for aname, act in actions(mut).items():
        for cname, f in post.items():
            n += 1
            text = "\n".join([decls(), pre, step(act), f"(assert (not {f}))", "(check-sat)"])
            tag = f"{aname.split(':')[0]}__{cname.split()[0]}".replace("(", "_").replace(")", "").replace(", ", "_")
            r = solve(text, z3, dump if not mut else None, tag)
            if r != "unsat":
                open_.append(f"{aname.split(':')[0]}  breaks  {cname}  ({r})")
    return n, open_


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--z3", default=shutil.which("z3") or "z3")
    ap.add_argument("--dump")
    args = ap.parse_args()
    dump = Path(args.dump) if args.dump else None
    if dump is not None:
        dump.mkdir(parents=True, exist_ok=True)

    # Init: nothing inside, no permits, nobody holds, the guard open
    init = [decls()]
    for r, sorts in REL.items():
        bound = " ".join(f"({'xwy'[k]} {srt})" for k, srt in enumerate(sorts))
        argl = " ".join("xwy"[k] for k in range(len(sorts)))
        init.append(f"(assert (forall ({bound}) (not ({r} {argl}))))")
    init.append("(assert (= guard open))")
    bad = [c for c, f in inv("").items()
           if solve("\n".join(init + [f"(assert (not {f}))", "(check-sat)"]), args.z3, None, "init") != "unsat"]
    print(f"Init => Inv: {'proved' if not bad else 'NOT proved: ' + ', '.join(bad)}")

    # the invariant is not empty of states, and every action can happen in a state that satisfies it
    pre = "\n".join(f"(assert {f})" for f in inv("").values())
    dead = [a for a, act in actions().items()
            if solve("\n".join([decls(), pre, step(act), "(check-sat)"]), args.z3, None, "enabled") != "sat"]
    print(f"every action is enabled in some state of Inv: {'yes' if not dead else 'NO: ' + ', '.join(dead)}")

    n, open_ = check("", args.z3, dump)
    print(f"Inv /\\ A => Inv': {n - len(open_)} of {n} obligations proved ({len(actions())} actions x "
          f"{len(inv(''))} conjuncts)")
    for o in open_:
        print("   NOT PROVED:", o)

    print("with one rule removed, the invariant is no longer inductive:")
    ok = not bad and not dead and not open_
    for mut in MUTATIONS:
        _, o = check(mut, args.z3, None)
        print(f"   {mut:<56} {'-> ' + o[0] if o else 'STILL INDUCTIVE (the encoding does not see this rule)'}")
        ok = ok and bool(o)
    print("conditions that the other rules imply (the invariant is inductive without them):")
    for mut in IMPLIED:
        _, o = check(mut, args.z3, None)
        print(f"   {mut:<56} {'implied' if not o else 'NOT implied -> ' + o[0]}")
        ok = ok and not o
    print("RESULT:", "S1, S2 and S3 hold for any number of machines, zones and permits" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
