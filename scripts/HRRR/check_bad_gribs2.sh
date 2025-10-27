#!/usr/bin/env bash
# Verify HRRR f01 and f06; repair from previous hour if missing/corrupt
# Usage: ./verify_and_repair_hrrr.sh /path/to/hrrr.YYYYMMDD

set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/hrrr.YYYYMMDD" >&2
  exit 1
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

# Return 0 if file exists, nonzero size, and wgrib2 can read it
check_ok () {
  local f="$1"
  [[ -s "$f" ]] || return 1
  # Quiet probe; wgrib2 returns nonzero on corrupt/invalid
  wgrib2 "$f" -v0 >/dev/null 2>&1
}

# Build file name for cycle hour HH and forecast FF (numeric), in directory DIR
fname () {
  local dir="$1" hh="$2" ff="$3"
  printf "%s/hrrr.t%02dz.wrfsfcf%02d.grib2" "$dir" "$hh" "$ff"
}

# Given a directory name .../hrrr.YYYYMMDD, extract YYYYMMDD
day_yyyymmdd () {
  basename "$1" | sed -E 's/^hrrr\.([0-9]{8})$/\1/'
}

# Compute previous cycle (YYYYMMDD, HH) from (YYYYMMDD, HH)
prev_cycle () {
  local ymd="$1" hh="$2"
  local stamp
  stamp=$(date -u -d "${ymd} ${hh}:00:00 -1 hour" +%Y%m%d%H)
  echo "${stamp:0:8} ${stamp:8:2}"
}

# Resolve directory for a YYYYMMDD (could be previous day)
dir_for_day () {
  local ymd="$1"
  local parent
  parent="$(dirname "$DAY_DIR")"   # parent directory that contains hrrr.YYYYMMDD
  echo "${parent}/hrrr.${ymd}"
}

# ---- main loop ----

YMDSRC="$(day_yyyymmdd "$DAY_DIR")"
if [[ ! "$YMDSRC" =~ ^[0-9]{8}$ ]]; then
  echo "ERROR: Could not parse YYYYMMDD from directory name: $DAY_DIR" >&2
  exit 1
fi

echo "Verifying f01 & f06 in: $DAY_DIR"

# Hours 00..23
for HH in $(seq -w 0 23); do
  # Targets
  F01="$(fname "$DAY_DIR" "$HH" 1)"
  F06="$(fname "$DAY_DIR" "$HH" 6)"

  # ----- Check/repair f01 -----
  if ! check_ok "$F01"; then
    echo "Repair f01 for ${YMDSRC} ${HH}z → missing/corrupt: $(basename "$F01")"
    # Source: previous hour's f02
    read -r PREV_YMD PREV_HH < <(prev_cycle "$YMDSRC" "$HH")
    PREV_DIR="$(dir_for_day "$PREV_YMD")"
    SRC_F02="$(fname "$PREV_DIR" "$PREV_HH" 2)"

    if [[ -s "$SRC_F02" ]] && wgrib2 "$SRC_F02" -v0 >/dev/null 2>&1; then
      # Ensure we're operating in the target directory (copy scripts expect cwd)
      pushd "$DAY_DIR" >/dev/null
      "$COPY_1" "$SRC_F02" "$F01"
      popd >/dev/null
      echo "Created: $(basename "$F01") from $(basename "$SRC_F02")"
    else
      echo "ERROR: Cannot repair f01; source invalid: $SRC_F02" >&2
    fi
  fi

  # ----- Check/repair f06 -----
  if ! check_ok "$F06"; then
    echo "Repair f06 for ${YMDSRC} ${HH}z → missing/corrupt: $(basename "$F06")"
    # Source: previous hour's f07
    read -r PREV_YMD PREV_HH < <(prev_cycle "$YMDSRC" "$HH")
    PREV_DIR="$(dir_for_day "$PREV_YMD")"
    SRC_F07="$(fname "$PREV_DIR" "$PREV_HH" 7)"

    if [[ -s "$SRC_F07" ]] && wgrib2 "$SRC_F07" -v0 >/dev/null 2>&1; then
      pushd "$DAY_DIR" >/dev/null
      "$COPY_6" "$SRC_F07" "$F06"
      popd >/dev/null
      echo "Created: $(basename "$F06") from $(basename "$SRC_F07")"
    else
      echo "ERROR: Cannot repair f06; source invalid: $SRC_F07" >&2
    fi
  fi
done

echo "Done."
