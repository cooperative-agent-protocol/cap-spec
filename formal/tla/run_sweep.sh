#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 CAP Authors
#
# Reproducible TLA+ model-checking sweep for the CAP formal models.
#
# Runs every (model, config) pair below, checks each verdict against its
# EXPECTED outcome, captures the full TLC log under logs/, and prints a
# Markdown summary table. The negative results (deny/retry starvation, the
# no-timeout reservation liveness) are first-class: the script FAILS if any
# verdict does not match its expectation, so an "expected counterexample"
# that silently starts passing (or vice versa) is caught.
#
# Usage:
#   ./run_sweep.sh            # full sweep (large instances may take minutes)
#   ./run_sweep.sh --fast     # skip the > ~10s instances (N4R2*, N5R2, N3R2 live)
#
# Requires Java >= 11 and tla2tools.jar (>= v1.8.0) in this directory.

set -u
cd "$(dirname "$0")"

JAR="tla2tools.jar"
JAR_SHA256="237332bdcc79a35c7d26efa7b82c77c85c2744591c5598673a8a45085ff2a4fb"
JAR_URL="https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"

FAST=0
[ "${1:-}" = "--fast" ] && FAST=1

mkdir -p logs

# --- Acquire and verify tla2tools.jar ---------------------------------------
if [ ! -f "$JAR" ]; then
  echo "Downloading $JAR ..."
  curl -sL -o "$JAR" "$JAR_URL"
fi
got="$(shasum -a 256 "$JAR" | awk '{print $1}')"
if [ "$got" != "$JAR_SHA256" ]; then
  echo "ERROR: $JAR sha256 mismatch."
  echo "  expected $JAR_SHA256"
  echo "  got      $got"
  exit 2
fi

JAVA_OPTS="-XX:+UseParallelGC -Xmx8g"

# model | config | spec-base | expected (PASS|FAIL) | slow (1=skipped by --fast)
RUNS=(
  "TaskState|TaskState.cfg|TaskState|PASS|0"
  "ReservationState|ReservationState.cfg|ReservationState|PASS|0"
  "ReservationState|ReservationState_notimeout.cfg|ReservationState|FAIL|0"
  "ReservationState|ReservationState_notimeout_strong.cfg|ReservationState|PASS|0"
  "MachineMode|MachineMode.cfg|MachineMode|PASS|0"
  "MachineMode|MachineMode_nofault.cfg|MachineMode|PASS|0"
  "ReservationFencing|ReservationFencing_fenced.cfg|ReservationFencing|PASS|0"
  "ReservationFencing|ReservationFencing_unfenced.cfg|ReservationFencing|FAIL|0"
  "SafetySupervisor|SafetySupervisor_priority.cfg|SafetySupervisor|PASS|0"
  "SafetySupervisor|SafetySupervisor_nopriority.cfg|SafetySupervisor|FAIL|0"
  "MultiResource|MultiResource_ordered.cfg|MultiResource|PASS|0"
  "MultiResource|MultiResource_unordered.cfg|MultiResource|FAIL|0"
  "ByzantineReservation|ByzantineReservation_trusted.cfg|ByzantineReservation|PASS|0"
  "ByzantineReservation|ByzantineReservation_untrusted.cfg|ByzantineReservation|FAIL|0"
  "TimedHandover|TimedHandover_enforced.cfg|TimedHandover|PASS|0"
  "TimedHandover|TimedHandover_unenforced.cfg|TimedHandover|FAIL|0"
  "CAPCoordination|CAPCoordination_safety.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_N2R1.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_N3R1.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_N3R2.cfg|CAPCoordination|PASS|1"
  "CAPCoordination|CAPCoordination_N4R2.cfg|CAPCoordination|PASS|1"
  "CAPCoordination|CAPCoordination_N4R2_nosym.cfg|CAPCoordination|PASS|1"
  "CAPCoordination|CAPCoordination_N5R2.cfg|CAPCoordination|PASS|1"
  "CAPCoordination|CAPCoordination_live_N2R1_retry.cfg|CAPCoordination|FAIL|0"
  "CAPCoordination|CAPCoordination_live_N2R1_queued.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_live_N3R1_queued.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_live_N3R2_queued.cfg|CAPCoordination|PASS|1"
  "CAPCoordination|CAPCoordination_ho_N2R1_atomic.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_ho_N3R1_atomic.cfg|CAPCoordination|PASS|0"
  "CAPCoordination|CAPCoordination_ho_N3R1_naive.cfg|CAPCoordination|FAIL|0"
)

printf '\n%-40s %-6s %-6s %12s %12s %8s\n' "config" "exp" "got" "generated" "distinct" "time"
printf '%s\n' "--------------------------------------------------------------------------------------"

fails=0
SUMMARY=""
for row in "${RUNS[@]}"; do
  IFS='|' read -r model cfg base exp slow <<< "$row"
  if [ "$FAST" = "1" ] && [ "$slow" = "1" ]; then
    printf '%-40s %-6s %-6s %12s\n' "$cfg" "$exp" "SKIP" "(--fast)"
    continue
  fi
  log="logs/${cfg%.cfg}.log"
  start=$(date +%s)
  java $JAVA_OPTS -jar "$JAR" -workers auto -config "$cfg" "$base.tla" >| "$log" 2>&1
  end=$(date +%s)
  elapsed=$((end - start))

  if grep -q "Model checking completed. No error has been found" "$log"; then
    got="PASS"
  elif grep -qE "Error: (Invariant|Temporal|Property|.*violated|.*were violated)|Error: The following behavior constitutes a counter-example|Error: Deadlock reached" "$log"; then
    got="FAIL"
  else
    got="ERR"
  fi
  gen=$(grep -Eo '[0-9,]+ states generated' "$log" | tail -1 | grep -Eo '^[0-9,]+')
  dist=$(grep -Eo '[0-9,]+ distinct states found' "$log" | tail -1 | grep -Eo '^[0-9,]+')

  mark="ok"
  if [ "$got" != "$exp" ]; then mark="MISMATCH"; fails=$((fails+1)); fi
  printf '%-40s %-6s %-6s %12s %12s %6ss  %s\n' "$cfg" "$exp" "$got" "${gen:-?}" "${dist:-?}" "$elapsed" "$mark"
  SUMMARY+="| \`$cfg\` | $exp | $got | ${gen:-?} | ${dist:-?} | ${elapsed}s |\n"
done

echo
echo "Markdown rows:"
printf "$SUMMARY"
echo

if [ "$fails" -gt 0 ]; then
  echo "FAILURE: $fails verdict(s) did not match expectation."
  exit 1
fi
echo "All verdicts matched expectations."
