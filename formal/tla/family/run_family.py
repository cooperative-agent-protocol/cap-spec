#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 CAP Authors
"""Model-check every member of the reservation-scheme family in OccupancyHandover.tla.

The family is spanned by five design choices (see the module header):
arbitration x entry gate x release x expiry x succession = 3 x 3 x 2 x 3 x 2 = 108
combinations. Designated succession needs an arbiter to designate, so the 18
combinations with Arb = "none" and Succession = "designated" are excluded: 90 remain.

For each setting (a choice of assumptions and environment) and each combination,
the script runs TLC with all requested properties; when one is violated it records
the property and TLC's shortest counterexample (breadth-first search), drops that
property and runs again, until the rest hold. The result is, per combination, the
set of properties that hold and a counterexample for each one that does not.

Usage:
  python3 run_family.py --setting base                # all 90 combinations
  python3 run_family.py --setting lossy --only CAP,LeaseFencedVacate
  python3 run_family.py --setting trivial             # non-triviality (NotCycle)

Requires Java >= 11 and tla2tools.jar (v1.8.0) one directory up (see ../run_sweep.sh).
"""
from __future__ import annotations

import argparse
import csv
import itertools
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HERE = Path(__file__).resolve().parent
TLA_DIR = HERE.parent
JAR = TLA_DIR / "tla2tools.jar"
SPEC = "OccupancyHandover.tla"

DIMS = {
    "Arb": ["none", "deny", "queue"],
    "Gate": ["none", "local", "permit"],
    "Release": ["onDone", "onVacate"],
    "Expiry": ["none", "ttl", "ttlVacate"],
    "Succession": ["free", "designated"],
}

# Named members of the family (the schemes compared in the paper).
NAMED = {
    "MutexOnDone": dict(Arb="deny", Gate="local", Release="onDone", Expiry="none", Succession="free"),
    "MutexGroup": dict(Arb="deny", Gate="local", Release="onVacate", Expiry="none", Succession="free"),
    "LeaseFenced": dict(Arb="deny", Gate="permit", Release="onDone", Expiry="ttl", Succession="free"),
    "LeaseFencedVacate": dict(Arb="deny", Gate="permit", Release="onVacate", Expiry="ttlVacate", Succession="free"),
    "CAP": dict(Arb="queue", Gate="permit", Release="onVacate", Expiry="ttlVacate", Succession="designated"),
}

BASE_ENV = dict(SensorSound=True, TimingSound=True, AuthOK=True, Faults=True,
                Restart="durable", BootScoped=True, GraceWait=True, MaxGen=3, MaxBoot=1)

SETTINGS = {
    # main comparison: all assumptions hold, machine faults, arbiter restarts keep state
    "base": dict(env={}, props=["S1", "S2", "S3", "G1", "G2"]),
    # arbiter restarts that lose state
    "lossy": dict(env=dict(Restart="lossy"), props=["S1", "S2", "S3", "G1", "G2"]),
    # assumption ablations (Proposition 3); run on the schemes that pass "lossy" or "base"
    "noA2": dict(env=dict(SensorSound=False), props=["S1", "S2", "S3"]),
    "noA4": dict(env=dict(TimingSound=False, Restart="lossy"), props=["S1", "S2", "S3"]),
    "noA5": dict(env=dict(AuthOK=False), props=["S1", "S2", "S3"]),
    "noBoot": dict(env=dict(BootScoped=False, Restart="lossy"), props=["S1", "S2", "S3"]),
    # the timing assumption alone (restarts keep the journal)
    "noA4d": dict(env=dict(TimingSound=False), props=["S1", "S2", "S3"]),
    # no grace period after a lossy restart, permits still boot-scoped
    "noGrace": dict(env=dict(GraceWait=False, Restart="lossy"), props=["S1", "S2", "S3"]),
    # non-triviality: a second machine can follow the first (NotCycle is expected VIOLATED)
    "trivial": dict(env=dict(Faults=False, Restart="none"), props=["NotCycle"]),
    # liveness G4 (a crashed holder eventually recovers or loses the zone) under LiveSpec's fairness
    "liveG4": dict(env=dict(Restart="none"), props=["G4"], temporal=True),
}


def combo_name(c: dict) -> str:
    for name, spec in NAMED.items():
        if spec == c:
            return name
    return "-".join(c[k] for k in DIMS)


def family() -> list[dict]:
    out = []
    for vals in itertools.product(*DIMS.values()):
        c = dict(zip(DIMS, vals))
        if c["Arb"] == "none" and c["Succession"] == "designated":
            continue  # designation needs an arbiter
        out.append(c)
    return out


def tla_value(v) -> str:
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, int):
        return str(v)
    return f'"{v}"'


def write_cfg(path: Path, combo: dict, env: dict, props: list[str], machines: list[str],
              temporal: bool = False) -> None:
    lines = ["SPECIFICATION LiveSpec" if temporal else "SPECIFICATION Spec", "CONSTANTS",
             "    Machines = {" + ", ".join(f'"{m}"' for m in machines) + "}",
             "    Incompatible <- AllCarrierPairs"]
    for k, v in {**combo, **env}.items():
        lines.append(f"    {k} = {tla_value(v)}")
    if temporal:
        lines.append("PROPERTIES")
    else:
        lines.append("INVARIANTS")
        lines.append("    TypeOK")
    lines += [f"    {p}" for p in props]
    lines.append("CHECK_DEADLOCK FALSE")
    path.write_text("\n".join(lines) + "\n")


VIOL_RE = re.compile(r"(?:Invariant|Temporal property) (\w+) (?:is|was) violated")
TEMP_RE = re.compile(r"Temporal properties were violated")
STATES_RE = re.compile(r"([\d,]+) distinct states found")
ACT_RE = re.compile(r"^State \d+: <([A-Za-z]+)(\([^)]*\))?")


def run_tlc(cfg: Path, workers: int, java: str, metadir: Path) -> tuple[str | None, int, list[str], str]:
    cmd = [java, "-XX:+UseParallelGC", "-Xmx6g", "-jar", str(JAR), "-workers", str(workers),
           "-metadir", str(metadir), "-config", str(cfg), SPEC]
    proc = subprocess.run(cmd, cwd=TLA_DIR, capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    for f in TLA_DIR.glob("OccupancyHandover_TTrace_*.tla"):
        f.unlink(missing_ok=True)
    m = VIOL_RE.search(out)
    if m is None and TEMP_RE.search(out):
        m = re.search(r"(Temporal)", out)
    st = STATES_RE.findall(out)
    states = int(st[-1].replace(",", "")) if st else -1
    if m is None and "No error has been found" not in out:
        raise RuntimeError(f"TLC did not finish cleanly for {cfg}:\n{out[-3000:]}")
    trace = []
    if m:
        for line in out.splitlines():
            a = ACT_RE.match(line)
            if a:
                trace.append(a.group(1) + (a.group(2) or ""))
    name = (m.group(1) if m else None)
    return name, states, trace, out


def check_combo(combo: dict, setting: str, workers: int, java: str, machines: list[str],
                tracedir: Path) -> dict:
    cfg_spec = SETTINGS[setting]
    env = {**BASE_ENV, **cfg_spec["env"]}
    remaining = list(cfg_spec["props"])
    result = {"scheme": combo_name(combo), **combo, "setting": setting,
              "holds": [], "fails": {}, "states": 0, "seconds": 0.0}
    t0 = time.time()
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        i = 0
        while remaining:
            cfg = td / f"run{i}.cfg"
            write_cfg(cfg, combo, env, remaining, machines, temporal=bool(cfg_spec.get("temporal")))
            viol, states, trace, out = run_tlc(cfg, workers, java, td / f"meta{i}")
            result["states"] = max(result["states"], states)
            if viol is None:
                result["holds"] += remaining
                remaining = []
            elif cfg_spec.get("temporal"):
                for prop in remaining:          # a temporal violation: TLC names no property; one is checked per run
                    result["fails"][prop] = trace
                (tracedir / f"{result['scheme']}__{remaining[0]}.txt").write_text(
                    "\n".join(trace) + "\n\n" + out[out.find("Error:"):][:20000])
                remaining = []
            else:
                result["fails"][viol] = trace
                (tracedir / f"{result['scheme']}__{viol}.txt").write_text(
                    "\n".join(trace) + "\n\n" + out[out.find("Error: The behavior"):][:20000])
                remaining.remove(viol)
            i += 1
    result["seconds"] = round(time.time() - t0, 1)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--setting", required=True, choices=sorted(SETTINGS))
    ap.add_argument("--only", default="", help="comma-separated scheme names (named or dash-joined)")
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--machines", default="c1,c2")
    ap.add_argument("--java", default=os.environ.get("TLA_JAVA", "java"))
    ap.add_argument("--tag", default="", help="name of the result files for an --only subset (e.g. safe12)")
    args = ap.parse_args()

    combos = family()
    if args.only:
        wanted = set(args.only.split(","))
        combos = [c for c in combos if combo_name(c) in wanted]
    resdir = HERE / "results"
    tracedir = resdir / "traces" / args.setting
    tracedir.mkdir(parents=True, exist_ok=True)
    machines = args.machines.split(",")
    print(f"{len(combos)} combinations, setting={args.setting}, machines={machines}", flush=True)

    rows = []
    with ThreadPoolExecutor(max_workers=args.parallel) as ex:
        futs = {ex.submit(check_combo, c, args.setting, args.workers, args.java, machines, tracedir): c
                for c in combos}
        for f in as_completed(futs):
            r = f.result()
            rows.append(r)
            print(f"{r['scheme']:<40} holds={','.join(r['holds']) or '-':<20} "
                  f"fails={','.join(r['fails']) or '-':<14} states={r['states']} t={r['seconds']}s", flush=True)

    rows.sort(key=lambda r: [r[k] for k in DIMS])
    suffix = "" if not args.only else "_" + (args.tag or "_".join(sorted(args.only.split(",")))[:60])
    with open(resdir / f"{args.setting}{suffix}.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        props = SETTINGS[args.setting]["props"]
        w.writerow(["scheme", *DIMS, *props, "states", "seconds"])
        for r in rows:
            w.writerow([r["scheme"], *[r[k] for k in DIMS],
                        *[("holds" if p in r["holds"] else "fails") for p in props],
                        r["states"], r["seconds"]])
    (resdir / f"{args.setting}{suffix}.json").write_text(json.dumps(rows, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
