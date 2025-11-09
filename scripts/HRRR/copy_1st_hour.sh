#!/usr/bin/env bash
# Script to copy previous 2nd hour and make it the 1st for the following
#
# Example:
#   copy_1st_hour.sh /abs/path/hrrr.t09z.wrfsfcf02.grib2 /abs/path/hrrr.t10z.wrfsfcf01.grib2
#

set -euo pipefail

SOURCE_FILE=${1:?SRC missing}
CREATED_FILE=${2:?DEST missing}

# Must be f02
if [[ ! "$SOURCE_FILE" =~ wrfsfcf02\.grib2$ ]]; then
  echo "ERROR(copy_1): SRC is not an f02 file: $SOURCE_FILE" >&2
  exit 3
fi

# Below should match the variables in the HRRR file, except for precipitation
HRRR_VARIABLES="HGT|TMP|RH|UGRD|VGRD|TCDC|DSWRF|VBDSF|VDDSF|DLWRF|APCP:surface:1-2 hour"
CREATED_HOUR=1

# Adjust datetime stamp and forecast time
wgrib2 "$SOURCE_FILE" \
  -match "${HRRR_VARIABLES}" \
  -set_date +1hr \
  -set_ftime "${CREATED_HOUR} hour fcst" \
  -grib_out "$CREATED_FILE"

# Print to verify output
echo " ** Result **"
wgrib2 -v2 "$CREATED_FILE"

# Clean up ".missing" files if created empty
find "$(dirname "$CREATED_FILE")" -maxdepth 1 -type f -name "$(basename "$CREATED_FILE").missing" -size 0 -delete

# Safer default: keep donor; uncomment to remove after successful creation
# rm -f -- "$SOURCE_FILE"
