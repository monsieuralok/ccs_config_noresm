#!/bin/bash
#
# make_filelist.sh - turn one or more NorESM/CESM resolved-input listings
#                    into a single file list for the CDL cache hydrator.
#
# Usage:
#   ./make_filelist.sh -o OUTPUT [-d CUTDIR] INPUT [INPUT ...]
#
# Examples:
#   ./make_filelist.sh -o case-01.filelist input.txt
#   ./make_filelist.sh -o case-01.filelist atm_in lnd_in ocn_in ice_in
#   ./make_filelist.sh -o case-01.filelist *_in
#   ./make_filelist.sh -o case-01.filelist -d mydata inputs/*.txt
#
# Options:
#   -o OUTPUT   file list to write                     (required)
#   -d CUTDIR   directory to cut the path at           (default: inputdata)
#   -h          show this help
#
# All inputs are merged into ONE list, sorted, with duplicates removed - so
# files referenced by several components appear only once.
#
# It reads lines of the form
#     liqopticsfile = /cluster/work/projects/nn9560k/inputdata//atm/cam/x.nc
# and writes
#     atm/cam/x.nc

set -euo pipefail          # stop on any error or unset variable

OUTPUT=""
CUTDIR="noresm/"

usage() {
    cat <<'EOF'
make_filelist.sh - build a CDL hydrator file list from experiment input files

Usage:
  ./make_filelist.sh -o OUTPUT [-d CUTDIR] INPUT [INPUT ...]

Options:
  -o OUTPUT   file list to write                  (required)
  -d CUTDIR   directory to cut the path at        (default: inputdata)
  -h          show this help

Examples:
  ./make_filelist.sh -o case-01.filelist input.txt
  ./make_filelist.sh -o case-01.filelist atm_in lnd_in ocn_in
  ./make_filelist.sh -o case-01.filelist *_in
  ./make_filelist.sh -o case-01.filelist -d mydata inputs/*.txt
EOF
    exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Read the options. getopts handles "-o name" and "-d name"; whatever is left
# over after the options is the list of input files.
# ---------------------------------------------------------------------------
while getopts ":o:d:h" opt; do
    case "$opt" in
        o) OUTPUT="$OPTARG" ;;
        d) CUTDIR="$OPTARG" ;;
        h) usage 0 ;;
        \?) echo "ERROR: unknown option -$OPTARG" >&2; usage 1 ;;
        :)  echo "ERROR: option -$OPTARG needs a value" >&2; usage 1 ;;
    esac
done
shift $((OPTIND - 1))      # drop the options, leaving only the input files

if [ -z "$OUTPUT" ]; then
    echo "ERROR: no output file given (use -o)" >&2
    usage 1
fi
if [ "$#" -eq 0 ]; then
    echo "ERROR: no input files given" >&2
    usage 1
fi

# Check every input exists before doing any work, so a typo in the fifth
# filename does not leave you with a half-built list.
MISSING=0
for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: input file not found: $f" >&2
        MISSING=1
    fi
done
[ "$MISSING" -eq 0 ] || exit 1

echo "reading $# input file(s), cutting paths at /${CUTDIR}/"

# ---------------------------------------------------------------------------
# Helpers.
#
# NOTE the "|| true" around every grep. Under "set -o pipefail" a grep that
# matches nothing counts as a failed pipeline, which would abort the script
# silently before the output file was ever written. "No matches" is a normal
# outcome here, not an error, so it must be tolerated explicitly.
# ---------------------------------------------------------------------------

# All right-hand-side values: everything after " = " on each line.
values() {
    awk -F' = ' 'NF>1 {print $NF}' "$@"
}

# Values under the cut directory, turned into hydrator keys.
extract() {
    values "$@" \
      | { grep "/${CUTDIR}/" || true; } \
      | sed "s|.*/${CUTDIR}/*||" \
      | tr -s '/' \
      | { grep -E '[^/]+\.[^/]+$' || true; } \
      | sort -u
}

# ---------------------------------------------------------------------------
# Per-file report first, so you can see which input contributed what. Useful
# when a component you expected to add files turns out to add none.
# ---------------------------------------------------------------------------
for f in "$@"; do
    COUNT=$(extract "$f" | wc -l)
    printf '  %-40s %5d file(s)\n' "$(basename "$f")" "$COUNT"
done

# ---------------------------------------------------------------------------
# The combined list. "$@" is every input file, so awk reads them all in one
# pass; the final sort -u merges and de-duplicates across files.
# ---------------------------------------------------------------------------
extract "$@" > "$OUTPUT"

TOTAL=$(wc -l < "$OUTPUT")

# ---------------------------------------------------------------------------
# Nothing found? Say why, and show what IS in the input, so the next attempt
# is an informed one rather than a guess.
# ---------------------------------------------------------------------------
if [ "$TOTAL" -eq 0 ]; then
    echo
    echo "ERROR: no files extracted - wrote an empty $OUTPUT" >&2
    echo >&2

    ANYVALUE=$(values "$@" | { grep '^/' || true; } | head -1)
    if [ -z "$ANYVALUE" ]; then
        echo "No 'key = /path' lines were found at all. This script expects" >&2
        echo "lines with a space-equals-space separator, for example:" >&2
        echo "    liqopticsfile = /cluster/work/projects/nn9560k/inputdata//atm/cam/x.nc" >&2
        echo "Check the input with:  head -3 $1" >&2
    else
        echo "Paths were found, but none contain /${CUTDIR}/." >&2
        echo "The path roots present in your input are:" >&2
        values "$@" | { grep '^/' || true; } \
          | cut -d/ -f1-6 | sort | uniq -c | sort -rn | head -10 \
          | sed 's/^/    /' >&2
        echo >&2
        echo "Pick the directory your data sits under and pass it with -d," >&2
        echo "for example:  $0 -o $OUTPUT -d mydata $*" >&2
    fi
    exit 1
fi

# ---------------------------------------------------------------------------
# Success report.
# ---------------------------------------------------------------------------
SUM=0
for f in "$@"; do
    SUM=$(( SUM + $(extract "$f" | wc -l) ))
done

echo
echo "wrote $TOTAL unique file(s) to $OUTPUT"
if [ "$SUM" -gt "$TOTAL" ]; then
    echo "  ($(( SUM - TOTAL )) duplicate reference(s) merged)"
fi
echo "use it with:  manifest = $(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"

# ---------------------------------------------------------------------------
# Report what was left out. Silence would be worse than a long message here:
# a file missing from the list means the job fails hours later.
# ---------------------------------------------------------------------------

# Paths in the inputs that are not under the cut directory. Usually inside the
# model source tree, so not in CDL at all.
OUTSIDE=$(values "$@" | { grep '^/' || true; } \
          | { grep -v "/${CUTDIR}/" || true; } | sort -u)
if [ -n "$OUTSIDE" ]; then
    echo
    echo "NOT included - these paths are not under /${CUTDIR}/:"
    echo "$OUTSIDE" | sed 's/^/    /'
fi

# Settings that point at a folder rather than a specific file. The hydrator
# needs exact files, so these cannot go in the list - but the model may read
# other files from them.
FOLDERS=$(values "$@" \
          | { grep "/${CUTDIR}/" || true; } \
          | { grep -vE '[^/]+\.[^/]+$' || true; } \
          | sed "s|.*/${CUTDIR}/*||" | tr -s '/' | sort -u)
if [ -n "$FOLDERS" ]; then
    echo
    echo "NOT included - these name a folder, not a file:"
    echo "$FOLDERS" | sed 's/^/    /'
    echo "    -> if the model reads other files from these, add them by hand"
    echo "       or request the whole folder with a target_path config"
fi
