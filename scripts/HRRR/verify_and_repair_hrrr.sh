\
    #!/usr/bin/env bash
    # Verify HRRR f01 and f06; repair by donor *with the same valid time*
    # Usage: ./verify_and_repair_hrrr.sh /path/to/hrrr.YYYYMMDD
    #
    # Logic:
    #   - For missing/corrupt f01 at cycle HH: donor is previous-hour f02 (ff_donor=2) with same VT
    #       VT = (ymd HH) + 1h  → donor_cycle = VT - 2h  → donor file = t{donor_HH}z f02
    #   - For missing/corrupt f06 at cycle HH: donor is previous-hour f07 (ff_donor=7) with same VT
    #       VT = (ymd HH) + 6h  → donor_cycle = VT - 7h  → donor file = t{donor_HH}z f07
    #
    # This script prints its absolute path so you can confirm which copy is being executed.

    set -euo pipefail

    echo "Verifier: $(readlink -f "$0")"

    if [[ $# -ne 1 ]]; then
      echo "Usage: $0 /path/to/hrrr.YYYYMMDD" >&2
      exit 1
    fi

    DAY_DIR="$1"
    if [[ ! -d "$DAY_DIR" ]]; then
      echo "ERROR: day directory not found: $DAY_DIR" >&2
      exit 2
    fi

    # ---- GNU date wrapper (uses gdate on macOS if available) ----
    _date() {
      if command -v gdate >/dev/null 2>&1; then gdate "$@"; else date "$@"; fi
    }

    if ! command -v wgrib2 >/dev/null 2>&1; then
      echo "ERROR: wgrib2 not found in PATH" >&2
      exit 2
    fi

    # Helpers to copy/repair; fall back to plain cp if helpers are absent
    COPY_1="${COPY_1:-./copy_1st_hour.sh}"
    COPY_6="${COPY_6:-./copy_6th_hour.sh}"
    if [[ ! -x "$COPY_1" ]]; then
      COPY_1="cp --reflink=auto -f"
    fi
    if [[ ! -x "$COPY_6" ]]; then
      COPY_6="cp --reflink=auto -f"
    fi

    # File tester
    check_ok() {
      local f="$1"
      [[ -s "$f" ]] && wgrib2 "$f" -v0 >/dev/null 2>&1
    }

    # Build filename inside a given day directory (YYYYMMDD, HH, ff)
    build_path() {
      local ymd="$1" ; local HH="$2" ; local ff="$3"
      printf "%s/hrrr.t%sz.wrfsfcf%02d.grib2" "$(_resolve_dir "$ymd")" "$HH" "$ff"
    }

    # Resolve a directory (hrrr.YYYYMMDD), creating it if needed (cross-day donor)
    _resolve_dir() {
      local ymd="$1"
      local dir="$(dirname "$DAY_DIR")/hrrr.${ymd}"
      mkdir -p "$dir"
      printf "%s" "$dir"
    }

    # donor selection by valid time
    # args: src_ymd src_HH ff_target ff_donor
    
    donor_path_by_valid_time() {
      local ymd="$1" ; local HH="$2" ; local ff_target="$3" ; local ff_donor="$4"
      # Parse YYYYMMDD and HH into a hyphenated UTC datetime and then to epoch
      local Y="${ymd:0:4}"; local M="${ymd:4:2}"; local D="${ymd:6:2}"
      local base_epoch=$(_date -u -d "${Y}-${M}-${D} ${HH}:00:00" +%s) || {
        echo "ERROR: could not parse date for ${ymd} ${HH}Z" >&2; return 9; }
      # valid time epoch
      local vt_epoch=$(( base_epoch + ff_target*3600 ))
      # donor cycle epoch
      local donor_epoch=$(( vt_epoch - ff_donor*3600 ))
      # Format back to ymd/HH
      local vt=$(_date -u -d "@${vt_epoch}" +%Y%m%d%H)
      local donor=$(_date -u -d "@${donor_epoch}" +%Y%m%d%H)
      local vt_ymd="${vt:0:8}"; local vt_HH="${vt:8:2}"
      local d_ymd="${donor:0:8}"; local d_HH="${donor:8:2}"
      local ff=$(printf "%02d" "$ff_donor")
      local path="$(build_path "$d_ymd" "$d_HH" "$ff")"
      # echo "  • Donor selection (by VT): target ymd=${ymd} HH=${HH} ff=${ff_target} → VT=${vt}; donor cycle=${d_ymd} ${d_HH}Z ff=${ff} → $(basename "$path")"
      # printf "%s" "$path"
      echo "  • Donor selection (by VT): target ymd=${ymd} HH=${HH} ff=${ff_target} → VT=${vt}; donor cycle=${d_ymd} ${d_HH}Z ff=${ff} → $(basename "$path")" >&2
      printf "%s" "$path"
    }
    

    # Iterate expected cycles for the day directory based on files present (robust to partial hours)
    mapfile -t HOURS < <(find "$DAY_DIR" -maxdepth 1 -type f -name 'hrrr.t??z.wrfsfcf*.grib2' \
                         | sed -E 's@.*hrrr\.t([0-9]{2})z\..*@\1@' | sort -u)
    # If none found, assume 00..23
    if [[ ${#HOURS[@]} -eq 0 ]]; then
      HOURS=( $(seq -w 0 23) )
    fi

    YMD=$(basename "$DAY_DIR" | sed -E 's/^hrrr\.([0-9]{8}).*$/\1/')
    if ! [[ "$YMD" =~ ^[0-9]{8}$ ]]; then
      echo "ERROR: Could not parse YYYYMMDD from $DAY_DIR" >&2
      exit 2
    fi

    echo "Verifying day: $YMD in $DAY_DIR"
    echo "Hours considered: ${HOURS[*]}"

    for HH in "${HOURS[@]}"; do
      F01="$(build_path "$YMD" "$HH" 1)"
      F06="$(build_path "$YMD" "$HH" 6)"

      # ----- f01: donor is previous-hour f02 (VT-2h) -----
      if ! check_ok "$F01"; then
        echo "Repair f01 for ${YMD} ${HH}z → missing/corrupt: $(basename "$F01")"
        SRC_F02="$(donor_path_by_valid_time "$YMD" "$HH" 1 2)"
        # sanity checks
        if [[ ! "$(basename "$SRC_F02")" =~ ^hrrr\.t([0-9]{2})z\.wrfsfcf02\.grib2$ ]]; then
          echo "ERROR: Donor not an f02 file: $SRC_F02" >&2
          continue
        fi
        if [[ ! -s "$SRC_F02" ]] || ! wgrib2 "$SRC_F02" -v0 >/dev/null 2>&1; then
          echo "ERROR: Cannot repair f01; source invalid: $SRC_F02" >&2
          continue
        fi
        echo "Calling copy_1: SRC=$(basename "$SRC_F02")  →  DEST=$(basename "$F01")"
        $COPY_1 "$SRC_F02" "$F01"
      fi

      # ----- f06: donor is previous-hour f07 (VT-7h) -----
      if ! check_ok "$F06"; then
        echo "Repair f06 for ${YMD} ${HH}z → missing/corrupt: $(basename "$F06")"
        SRC_F07="$(donor_path_by_valid_time "$YMD" "$HH" 6 7)"
        if [[ ! "$(basename "$SRC_F07")" =~ ^hrrr\.t([0-9]{2})z\.wrfsfcf07\.grib2$ ]]; then
          echo "ERROR: Donor not an f07 file: $SRC_F07" >&2
          continue
        fi
        if [[ ! -s "$SRC_F07" ]] || ! wgrib2 "$SRC_F07" -v0 >/dev/null 2>&1; then
          echo "ERROR: Cannot repair f06; source invalid: $SRC_F07" >&2
          continue
        fi
        echo "Calling copy_6: SRC=$(basename "$SRC_F07")  →  DEST=$(basename "$F06")"
        $COPY_6 "$SRC_F07" "$F06"
      fi
    done

    echo "Done."
