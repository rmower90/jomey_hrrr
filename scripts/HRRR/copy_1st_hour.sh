#!/usr/bin/env bash
# Copy previous f02 into a new f01 for the next cycle, preserving valid time.
# Usage:
#   copy_1st_hour.sh /abs/path/to/hrrr.t19z.wrfsfcf02.grib2 /abs/path/to/hrrr.t20z.wrfsfcf01.grib2

set -euo pipefail

SRC="${1:?SRC missing}"
DEST="${2:?DEST missing}"

# Ensure absolute paths (helps logging)
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
DEST_DIR="$(cd "$(dirname "$DEST")" && pwd)"
DEST="${DEST_DIR}/$(basename "$DEST")"

if [[ ! -s "$SRC" ]]; then
  echo "ERROR(copy_1): Source not found or empty: $SRC" >&2
  exit 2
fi

# Require that SRC is an f02 file; DEST is an f01 file
[[ "$SRC"  =~ wrfsfcf02\.grib2$ ]] || { echo "ERROR(copy_1): SRC is not f02: $SRC" >&2; exit 3; }
[[ "$DEST" =~ wrfsfcf01\.grib2$ ]] || { echo "ERROR(copy_1): DEST is not f01: $DEST" >&2; exit_
