#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 CAP Authors
"""Three-machine TLC configurations for the schemes that are safe at two machines (OccupancyHandover.tla).

Machines are model values and the configurations use SYMMETRY Symm (sound for the invariants checked here), which
cuts the state space by up to 3! = 6. Writes <out>/m3_<setting>_<scheme>.cfg and <out>/order.txt.

  python3 gen_m3_cfgs.py <out-dir>
"""
from __future__ import annotations

import sys
from pathlib import Path

import run_family as rf

SAFE = ["deny-local-onVacate-none-designated", "MutexGroup", "deny-permit-onVacate-none-designated",
        "deny-permit-onVacate-none-free", "deny-permit-onVacate-ttlVacate-designated", "LeaseFencedVacate",
        "queue-local-onVacate-none-designated", "queue-local-onVacate-none-free",
        "queue-permit-onVacate-none-designated", "queue-permit-onVacate-none-free", "CAP",
        "queue-permit-onVacate-ttlVacate-free"]


def main() -> int:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    combos = {rf.combo_name(c): c for c in rf.family()}
    names = []
    for setting in ("base", "lossy"):
        env = {**rf.BASE_ENV, **rf.SETTINGS[setting]["env"]}
        for n in SAFE:
            c = combos[n]
            if setting == "lossy" and c["Gate"] != "permit":
                continue        # not safe under lossy restarts at two machines already
            props = ["S1", "S2", "S3"] + (["G1", "G2"] if c["Succession"] == "designated" else [])
            lines = ["SPECIFICATION Spec", "CONSTANTS", "    Machines = {c1, c2, c3}",
                     "    Incompatible <- AllCarrierPairs"]
            lines += [f"    {k} = {rf.tla_value(v)}" for k, v in {**c, **env}.items()]
            lines += ["SYMMETRY Symm", "INVARIANTS", "    TypeOK", *[f"    {p}" for p in props],
                      "CHECK_DEADLOCK FALSE"]
            name = f"m3_{setting}_{n}"
            (out / f"{name}.cfg").write_text("\n".join(lines) + "\n")
            names.append(name)
    (out / "order.txt").write_text("\n".join(names) + "\n")
    print(len(names), "configurations ->", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
