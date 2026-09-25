#!/usr/bin/env bash
# Runs baseline + both PgBouncer fixes and prints a summary.
# Usage: ./run-all.sh [explicit|jdbc] [seconds]
cd "$(dirname "$0")"
MODE="${1:-explicit}"
SECS="${2:-20}"
mkdir -p results

declare -A RES
for fix in none track reset; do
  FIX=$fix ./run.sh "$MODE" "$SECS" 2>&1 | tee "results/$MODE-$fix.log"
  line=$(grep '^RESULT' "results/$MODE-$fix.log" | tail -1)
  RES[$fix]="${line:-FAILED TO RUN (see results/$MODE-$fix.log)}"
  echo
done

echo "================ SUMMARY (mode=$MODE, ${SECS}s each) ================"
printf "%-8s %s\n" "none"  "${RES[none]}"
printf "%-8s %s\n" "track" "${RES[track]}"
printf "%-8s %s\n" "reset" "${RES[reset]}"
