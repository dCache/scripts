#!/bin/sh

set -e

usage() {
    echo "Usage: $0 [-h HOSTNAME] [-p PORT] [-d DBNAME] [-U USERNAME] [-D DATE] [-l LIMIT] [-s] [-o] FILENAME [ROOT [PREFIX]]"
    echo
    echo "Options:"
    echo "  -h Specifies the host name of the machine on which postgresql is running. Defaults"
    echo "     to connecting over a Unix-domain socket."
    echo "  -p Specifies the TCP port on which the postgresql server is listening for connections."
    echo "     Only used with -h. Defaults to 5432."
    echo "  -d Specifies the name of the database to connect to. Defaults to chimera."
    echo "  -U Connect to the database as the user username instead of the default."
    echo "  -D Specifies a cutoff date. Files created after this date are not included."
    echo "     Relative dates are allowed. Default is '1 day ago'."
    echo "  -l Specifies a limit on how many files to include. Mainly useful for testing."
    echo "  -s Include the size of each file in the dump."
    echo "  -o Order the dump by pathnames."
    echo
    echo "FILENAME is the output file name. Use “-” to output to STDOUT. ROOT is the root of the"
    echo "directory tree to dump. ROOT defaults to /. PREFIX is a path PREFIX to place in front"
    echo "of paths after ROOT has been striped off. Defaults to the value of ROOT."
    echo
    echo "Output is sorted unless a limit has been specified."
    exit 1
}

EXTRA_COLS=""

while getopts h:p:d:U:D:l:s:o f; do
  case "$f" in
  h) HOST="$OPTARG";;
  p) PORT="$OPTARG";;
  d) DATABASE="$OPTARG";;
  U) USERNAME="$OPTARG";;
  D) DATE="$OPTARG";;
  l) LIMIT="$OPTARG";;
  s) EXTRA_COLS="${EXTRA_COLS}, i.isize";;
  o) ORDER="path";;
  \?) usage;;
  esac
done

PORT="${PORT:-5432}"
DATABASE="${DATABASE:-chimera}"
DATE="${DATE:-1 day ago}"
DATE="$(date --date="${DATE}" --iso-8601=seconds)"

shift `expr $OPTIND - 1`

if [ $# -eq 0 -o $# -gt 3 ]; then
  usage
fi

OUTPUT="$1"
ROOT="${2:-/}"
ROOT="$(printf "%s" "${ROOT}" | sed 's|///*|/|g')"
PREFIX="${3:-$ROOT}"
PREFIX="$(printf "%s" "${PREFIX}" | sed 's|///*|/|g')"

if [ "$OUTPUT" = "-" ]; then
  OUTPUT=""
fi

if [ "$ROOT" = / ]; then
  START="(pnfsid2inumber('000000000000000000000000000000000000'), '${PREFIX%/}')"
else
  START="(path2inumber(pnfsid2inumber('000000000000000000000000000000000000'), '${ROOT#/}'), '${PREFIX%/}')"
fi

psql ${HOST:+-h $HOST} ${PORT:+-p $PORT} ${OUTPUT:+-o "$OUTPUT"} -t -A -f - $DATABASE $USERNAME <<EOF
\set ON_ERROR_STOP
WITH RECURSIVE paths(inumber, path) AS (
     VALUES $START
   UNION
     SELECT d.ichild, p.path||'/'||d.iname
     FROM paths p JOIN t_dirs d ON p.inumber = d.iparent
     WHERE d.iname != '.' AND d.iname != '..'
)
SELECT p.path${EXTRA_COLS} FROM paths p JOIN t_inodes i ON p.inumber = i.inumber
WHERE i.itype = 32768 ${DATE:+AND i.icrtime <= '$DATE'} ${ORDER:+ORDER BY $ORDER} ${LIMIT:+LIMIT ${LIMIT}};
EOF
