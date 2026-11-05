#!/bin/sh
# How much the agent has done, by table.
set -eu
. "$(dirname "$0")/_common.sh"
[ -f "$DB" ] || { echo "no database at $DB"; exit 1; }

for T in trigger thread decision ticket outbox; do
  printf "%-10s %s\n" "$T" "$(sqlite3 "$DB" "SELECT count(*) FROM $T")"
done
echo "outcomes"
sqlite3 "$DB" "SELECT json_extract(value,'\$.assignments[0].report.state') AS s, count(*)
               FROM ticket GROUP BY s ORDER BY 2 DESC;" 2>&1
