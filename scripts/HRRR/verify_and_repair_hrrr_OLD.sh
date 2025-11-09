#!/usr/bin/env bash
# Verify HRRR f01 and f06; repair from previous hour if missing/corrupt
# Usage: ./verify_and_repair_hrrr.sh /path/to/hrrr.YYYYMMDD

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/hrrr.YYYYMMDD" >&2
  exit 1
fi

if ! command -v wgrib2 >/dev/null 2>&1; then
  echo "ERROR: wgrib2 not found in PATH" >&2
  exit 2
fi

DAY_DIR="$1"
if [[ ! -d "$DAY_DIR" ]]; then
  echo "ERROR: Directory not found: $DAY_DIR" >&2
  exit 1
fi

# Resolve absolute path for robust cross-day calls
DAY_DIR="$(cd "$DAY_DIR" && pwd)"

# Require helper scripts to be alongside this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPY_1="${SCRIPT_DIR}/copy_1st_hour.sh"
COPY_6="${SCRIPT_DIR}/copy_6th_hour.sh"

for helper in "$COPY_1" "$COPY_6"; do
  if [[ ! -x "$helper" ]]; then
    echo "ERROR: Missing or not executable: $helper" >&2
    exit 1
  fi
done

# ---- helpers ----

check_ok () {
  local f="$1"
  [[ -s "$f" ]] || return 1
  wgrib2 "$f" -v0 >/dev/null 2>&1
}

fname () {
  local dir="$1" hh="$2" ff="$3"
  printf "%s/hrrr.t%02dz.wrfsfcf%02d.grib2" "$dir" "$((10#$hh))" "$ff"
}

day_yyyymmdd () {
  basename "$1" | sed -E 's/^hrrr\.([0-9]{8})$/\1/'
}

dir_for_day () {
  local ymd="$1"
  local parent
  parent="$(dirname "$DAY_DIR")"   # parent directory that contains hrrr.YYYYMMDD
  echo "${parent}/hrrr.${ymd}"
}

# Donor-by-valid-time selector:
#   For a missing target (ymd, HH, ff_target), its valid time is VT = (ymd HH) + ff_target hours.
#   We want a donor with the SAME valid time but lead ff_donor (usually ff_target+1).
#   So donor cycle time = VT - ff_donor hours.

# -- replace your donor_path_by_valid_time() with this --
donor_path_by_valid_time () {
  local ymd="$1" hh="$2" ff_target="$3" ff_donor="$4"

  # valid time of the TARGET
  local vt
  vt=$(date -u -d "${ymd} ${hh}:00:00 +${ff_target} hour" +%Y%m%d%H)

  # donor cycle = VT - ff_donor hours
  local dnr dnr_ymd dnr_hh dnr_dir src
  dnr=$(date -u -d "${vt:0:8} ${vt:8:2}:00:00 -${ff_donor} hour" +%Y%m%d%H)
  dnr_ymd=${dnr:0:8}
  dnr_hh=${dnr:8:2}
  dnr_dir="$(dir_for_day "$dnr_ymd")"
  src="$(fname "$dnr_dir" "$dnr_hh" "$ff_donor")"

  # LOG → stderr only
  >&2 echo "  • Donor selection (by VT): target ymd=${ymd} HH=${hh} ff=${ff_target} → VT=${vt}; donor cycle=${dnr_ymd} ${dnr_hh}Z ff=${ff_donor} → $(basename "$src")"

  # RETURN → stdout (only the path)
  printf "%s" "$src"
}

# ---- main loop ----

YMDSRC="$(day_yyyymmdd "$DAY_DIR")"
if [[ ! "$YMDSRC" =~ ^[0-9]{8}$ ]]; then
  echo "ERROR: Could not parse YYYYMMDD from directory name: $DAY_DIR" >&2
  exit 1
fi

echo "Verifying f01 & f06 in: $DAY_DIR"

for HH in $(seq -w 0 23); do
  F01="$(fname "$DAY_DIR" "$HH" 1)"
  F06="$(fname "$DAY_DIR" "$HH" 6)"

  # ----- Check/repair f01 (donor is previous hour's f02, equivalently donor-by-VT with ff_donor=2) -----
  if ! check_ok "$F01"; then
    echo "Repair f01 for ${YMDSRC} ${HH}z → missing/corrupt: $(basename "$F01")"
    SRC_F02="$(donor_path_by_valid_time "$YMDSRC" "$HH" 1 2)"

    # Enforce filename hour match and existence
    DNR_BASENAME="$(basename "$SRC_F02")"
    if [[ ! "$DNR_BASENAME" =~ ^hrrr\.t([0-9]{2})z\.wrfsfcf02\.grib2$ ]]; then
      echo "ERROR: Donor not an f02 file: $SRC_F02" >&2
      continue
    fi
    if [[ ! -s "$SRC_F02" ]] || ! wgrib2 "$SRC_F02" -v0 >/dev/null 2>&1; then
      echo "ERROR: Cannot repair f01; source invalid: $SRC_F02" >&2
      continue
    fi

    echo "Calling copy_1: SRC=$(basename "$SRC_F02")  →  DEST=$(basename "$F01")"
    "$COPY_1" "$SRC_F02" "$F01"
  fi

  # ----- Check/repair f06 (donor is previous hour's f07; donor-by-VT with ff_donor=7) -----
  if ! check_ok "$F06"; then
    echo "Repair f06 for ${YMDSRC} ${HH}z → missing/corrupt: $(basename "$F06")"
    SRC_F07="$(donor_path_by_valid_time "$YMDSRC" "$HH" 6 7)"

    if [[ ! "$(basename "$SRC_F07")" =~ ^hrrr\.t([0-9]{2})z\.wrfsfcf07\.grib2$ ]]; then
      echo "ERROR: Donor not an f07 file: $SRC_F07" >&2
      continue
    fi
    if [[ ! -s "$SRC_F07" ]] || ! wgrib2 "$SRC_F07" -v0 >/dev/null 2>&1; then
      echo "ERROR: Cannot repair f06; source invalid: $SRC_F07" >&2
      continue
    fi

    echo "Calling copy_6: SRC=$(basename "$SRC_F07")  →  DEST=$(basename "$F06")"
    "$COPY_6" "$SRC_F07" "$F06"
  fi
done

echo "Done."
