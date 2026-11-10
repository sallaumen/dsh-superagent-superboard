#!/bin/sh
# The last tickets and what each one reported. Read from the sqlite, not the API.
set -eu
. "$(dirname "$0")/_common.sh"

[ -f "$DB" ] || { echo "no database at $DB"; exit 1; }
LIMIT="${1:-10}"

sqlite3 "$DB" "
SELECT coalesce(json_extract(value,'\$.assignments[#-1].report.state'),'-') || '  ' ||
       coalesce(substr(json_extract(value,'\$.title'),1,46),'-') || '  ' ||
       coalesce(substr(json_extract(value,'\$.assignments[#-1].report.at'),1,16),'-')
FROM ticket ORDER BY rowid DESC LIMIT $LIMIT;" 2>&1
