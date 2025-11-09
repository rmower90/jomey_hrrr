#!/usr/bin/env bash
# Copy previous 7th hour file to synthesize the 6th hour for the following cycle.
#
# Example:
#   copy_6th_hour.sh /abs/path/hrrr.t09z.wrfsfcf07.grib2 /abs/path/hrrr.t10z.wrfsfcf06.grib2
#
# Logic:
#   - Non-precip fields: shift datetime +1hr, set ftime to "6 hour fcst".
#   - Precip (APCP): take "6-7 hour acc fcst" from donor, shift +1hr, relabel to "5-6 hour acc fcst".

set -euo pipefail

# --- args & sanity ---
SOURCE_FILE=${1:?SRC missing}
CREATED_FILE=${2:?DEST missing}

if ! command -v wgrib2 >/dev/null 2>&1; then
  echo "ERROR(copy_6): wgrib2 not found in PATH" >&2
  exit 2
fi

# Must be an f07 donor
if [[ ! "$SOURCE_FILE" =~ wrfsfcf07\.grib2$ ]]; then
  echo "ERROR(copy_6): SRC is not an f07 file: $SOURCE_FILE" >&2
  exit 3
fi

if [[ ! -s "$SOURCE_FILE" ]]; then
  echo "ERROR(copy_6): Source not found or empty: $SOURCE_FILE" >&2
  exit 4
fi

# --- config ---
# Match all desired non-precip variables; APCP handled separately
HRRR_VARIABLES='HGT|TMP|RH|UGRD|VGRD|TCDC|DSWRF|VBDSF|VDDSF|DLWRF'
CREATED_HOUR=6

TMP1="${CREATED_FILE}_1"
TMP2="${CREATED_FILE}_2"
cleanup() { rm -f -- "$TMP1" "$TMP2"; }
trap cleanup EXIT

# --- build non-precip fields (shift +1hr, set 6h lead) ---
wgrib2 "$SOURCE_FILE" \
  -match "$HRRR_VARIABLES" \
  -set_date +1hr \
  -set_ftime "${CREATED_HOUR} hour fcst" \
  -grib_out "$TMP1"

# --- build precip: take donor's 6-7h accumulation, shift +1hr → 5-6h accumulation ---
# If the donor lacks this message, fail loudly so the caller can handle it.
if ! wgrib2 "$SOURCE_FILE" -match "APCP:surface:${CREATED_HOUR}-7 hour acc fcst" -v0 >/dev/null 2>&1; then
  echo "ERROR(copy_6): Donor missing APCP message 'APCP:surface:${CREATED_HOUR}-7 hour acc fcst' in $SOURCE_FILE" >&2
  exit 5
fi

wgrib2 "$SOURCE_FILE" \
  -match "APCP:surface:${CREATED_HOUR}-7 hour acc fcst" \
  -set_date +1hr \
  -set_ftime "5-${CREATED_HOUR} hour acc fcst" \
  -grib_out "$TMP2"

# --- concatenate fields into final product ---
cat "$TMP1" "$TMP2" > "$CREATED_FILE"

# --- verify output ---
echo " ** Result **"
wgrib2 -v2 "$CREATED_FILE"

# --- clean up any empty .missing artifacts in the output directory ---
find "$(dirname "$CREATED_FILE")" -maxdepth 1 -type f -name "$(basename "$CREATED_FILE").missing" -size 0 -delete

# Safer default: keep donor; uncomment to remove only once you’re confident.
# rm -f -- "$SOURCE_FILE"
