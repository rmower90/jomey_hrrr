#!/usr/bin/env python3
"""
Stage 1 (diagnose): read-only pass over a water year's raw HRRR archive that
classifies every expected F01 and F06 file as ok / missing / corrupt and
writes a ledger CSV. Nothing is written into the raw archive.

"corrupt" means the file exists and is non-zero size but either wgrib2 can't
read it, or it's missing one of the specific GRIB messages PreprocessHRRR
actually consumes (load_single_f01 / load_single_prate in input.py) -- a file
can be "readable" and still be useless to processing if it's short a field.

Usage:
    python diagnose.py 2018 \
        --raw-base /glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw \
        --out ledger_2018.csv
"""
import argparse
import csv
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
from pathlib import Path

# Exact fields PreprocessHRRR reads out of each lead group (input.py).
# MET_PATTERNS and precip_pattern() are lead-agnostic building blocks reused
# by plan_repairs.py to validate candidate donor files at leads other than
# F01/F06.
MET_PATTERNS = [
    re.compile(r":TMP:2 m above ground:"),
    re.compile(r":RH:2 m above ground:"),
    re.compile(r":UGRD:10 m above ground:"),
    re.compile(r":VGRD:10 m above ground:"),
    re.compile(r":DSWRF:surface:"),
    re.compile(r":DLWRF:surface:"),
]


def precip_pattern(lead_num: int):
    """The donor's own most-recent 1-hour APCP accumulation bucket at `lead_num`."""
    return re.compile(rf":APCP:surface:{lead_num - 1}-{lead_num} hour acc fcst:")


def snow_pattern(lead_num: int):
    """The donor's own most-recent 1-hour WEASD accumulation bucket at `lead_num`."""
    return re.compile(rf":WEASD:surface:{lead_num - 1}-{lead_num} hour acc fcst:")


REQUIRED_PATTERNS = {
    "F01": MET_PATTERNS,
    "F06": [precip_pattern(6), snow_pattern(6)],
}
LEAD_NUMBER = {"F01": "01", "F06": "06"}


def discover_date_range(year_dir: Path):
    days = sorted(p.name for p in year_dir.glob("hrrr.????????") if p.is_dir())
    if not days:
        raise SystemExit(f"No hrrr.YYYYMMDD directories found under {year_dir}")
    first = date(int(days[0][5:9]), int(days[0][9:11]), int(days[0][11:13]))
    last_name = days[-1]
    last = date(int(last_name[5:9]), int(last_name[9:11]), int(last_name[11:13]))
    return first, last


def classify(path: Path, lead_group: str):
    if not path.exists() or path.stat().st_size == 0:
        return "missing", "no file / zero size"

    try:
        out = subprocess.run(
            ["wgrib2", str(path)],
            capture_output=True, text=True, timeout=30,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return "corrupt", f"wgrib2 invocation failed: {e}"

    if out.returncode != 0:
        return "corrupt", f"wgrib2 exit {out.returncode}: {out.stderr.strip()[:200]}"

    inventory = out.stdout
    missing_fields = [
        pat.pattern for pat in REQUIRED_PATTERNS[lead_group] if not pat.search(inventory)
    ]
    if missing_fields:
        return "corrupt", "missing field(s): " + ", ".join(missing_fields)

    return "ok", ""


def iter_targets(year_dir: Path, start: date, end: date, lead_groups):
    d = start
    while d <= end:
        ymd = d.strftime("%Y%m%d")
        for hh in range(24):
            for lg in lead_groups:
                fname = f"hrrr.t{hh:02d}z.wrfsfcf{LEAD_NUMBER[lg]}.grib2"
                path = year_dir / f"hrrr.{ymd}" / fname
                yield d, hh, lg, path
        d += timedelta(days=1)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("year", type=int, help="water year, e.g. 2018")
    ap.add_argument("--raw-base", default="/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw")
    ap.add_argument("--out", default=None, help="output ledger CSV path")
    ap.add_argument("--leads", default="F01,F06")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--month", default=None, help="restrict to one YYYY-MM for a quick test run")
    args = ap.parse_args()

    year_dir = Path(args.raw_base) / str(args.year)
    lead_groups = args.leads.split(",")
    out_path = Path(args.out) if args.out else Path(f"ledger_{args.year}.csv")

    start, end = discover_date_range(year_dir)
    if args.month:
        y, m = (int(x) for x in args.month.split("-"))
        start = date(y, m, 1)
        end = date(y + (m == 12), (m % 12) + 1, 1) - timedelta(days=1)
    print(f"Diagnosing {year_dir} over {start} .. {end}, leads={lead_groups}")

    targets = list(iter_targets(year_dir, start, end, lead_groups))
    print(f"Total targets: {len(targets)}")

    rows = []
    counts = {lg: {"ok": 0, "missing": 0, "corrupt": 0} for lg in lead_groups}

    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {
            ex.submit(classify, path, lg): (d, hh, lg, path)
            for d, hh, lg, path in targets
        }
        done = 0
        for fut in as_completed(futures):
            d, hh, lg, path = futures[fut]
            status, detail = fut.result()
            rows.append((d.isoformat(), hh, lg, status, detail, str(path)))
            counts[lg][status] += 1
            done += 1
            if done % 2000 == 0:
                print(f"  ... {done}/{len(targets)}")

    rows.sort(key=lambda r: (r[0], r[1], r[2]))
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "hour", "lead_group", "status", "detail", "path"])
        w.writerows(rows)

    print(f"\nWrote ledger: {out_path} ({len(rows)} rows)")
    for lg in lead_groups:
        c = counts[lg]
        print(f"  {lg}: ok={c['ok']} missing={c['missing']} corrupt={c['corrupt']}")


if __name__ == "__main__":
    main()
