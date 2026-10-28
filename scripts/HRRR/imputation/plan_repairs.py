#!/usr/bin/env python3
"""
Stage 2 (plan): read-only pass over a Stage 1 ledger that, for every
missing/corrupt F01 or F06 row, searches for a same-valid-time donor at
increasing hop distance and records the plan. Nothing is written or copied --
this only proposes actions for review before Stage 3 executes anything.

Donor rule (generalizes copy_1st_hour.sh / copy_6th_hour.sh): for a target at
(date, hour, lead), a donor N hours earlier in cycle time with lead+N has the
identical valid time. Hop distance is bounded by --max-lead (the longest lead
actually downloaded), so F01 (lead=1) can search up to N=max_lead-1 and F06
(lead=6) up to N=max_lead-6. The smallest working N is used (closest in time
= least forecast drift). If no donor exists within that bound, the row is
marked for the "interpolate" fallback instead -- see conversation design
notes, not computed here.

Usage:
    python plan_repairs.py ledger_2018.csv --out plan_2018.csv
"""
import argparse
import csv
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from diagnose import MET_PATTERNS, precip_pattern, snow_pattern

TARGET_LEAD = {"F01": 1, "F06": 6}


def donor_cycle(dt: datetime, hop: int):
    return dt - timedelta(hours=hop)


def find_donor(raw_base: Path, year: str, lead_group: str, dt: datetime, max_lead: int):
    target_lead = TARGET_LEAD[lead_group]
    for hop in range(1, max_lead - target_lead + 1):
        donor_lead = target_lead + hop
        d_dt = donor_cycle(dt, hop)
        donor_path = (
            raw_base / year / f"hrrr.{d_dt.strftime('%Y%m%d')}"
            / f"hrrr.t{d_dt.hour:02d}z.wrfsfcf{donor_lead:02d}.grib2"
        )
        # Donor must satisfy the field requirement at ITS OWN lead, not the
        # target's fixed lead (a precip donor's bucket is always its own
        # most-recent hour, e.g. an F09 donor has "8-9 hour acc fcst", never
        # "5-6").
        patterns = MET_PATTERNS if lead_group == "F01" else [precip_pattern(donor_lead), snow_pattern(donor_lead)]
        status, detail = classify_donor(donor_path, patterns)
        if status == "ok":
            return hop, d_dt, donor_lead, donor_path, detail
    return None


def classify_donor(path: Path, patterns):
    if not path.exists() or path.stat().st_size == 0:
        return "missing", "no file / zero size"
    out = subprocess.run(["wgrib2", str(path)], capture_output=True, text=True, timeout=30)
    if out.returncode != 0:
        return "corrupt", f"wgrib2 exit {out.returncode}"
    missing = [p.pattern for p in patterns if not p.search(out.stdout)]
    if missing:
        return "corrupt", "missing field(s): " + ", ".join(missing)
    return "ok", ""


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("ledger", help="Stage 1 ledger CSV")
    ap.add_argument("--raw-base", default="/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw")
    ap.add_argument("--max-lead", type=int, default=13)
    ap.add_argument("--year", default=None, help="defaults to parsing ledger_<year>.csv")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    ledger_rows = list(csv.DictReader(open(args.ledger)))
    bad_rows = [r for r in ledger_rows if r["status"] != "ok"]
    print(f"Ledger has {len(ledger_rows)} rows, {len(bad_rows)} need a repair plan")

    year = args.year or Path(args.ledger).stem.split("_")[-1]
    raw_base = Path(args.raw_base)
    out_path = Path(args.out) if args.out else Path(f"plan_{year}.csv")

    plan_rows = []
    counts = {"copy": 0, "interpolate": 0}
    for i, r in enumerate(bad_rows):
        dt = datetime.strptime(r["date"], "%Y-%m-%d") + timedelta(hours=int(r["hour"]))
        lead_group = r["lead_group"]
        result = find_donor(raw_base, year, lead_group, dt, args.max_lead)
        if result:
            hop, d_dt, donor_lead, donor_path, _ = result
            action = "copy"
            plan_rows.append([
                r["date"], r["hour"], lead_group, r["status"], action, hop,
                d_dt.strftime("%Y-%m-%d"), d_dt.hour, donor_lead, str(donor_path),
            ])
        else:
            action = "interpolate"
            plan_rows.append([
                r["date"], r["hour"], lead_group, r["status"], action, "",
                "", "", "", "no donor within max_lead bound",
            ])
        counts[action] += 1
        if (i + 1) % 100 == 0:
            print(f"  ... {i + 1}/{len(bad_rows)}")

    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "date", "hour", "lead_group", "initial_status", "action", "hop",
            "donor_date", "donor_hour", "donor_lead", "donor_path_or_note",
        ])
        w.writerows(plan_rows)

    print(f"\nWrote plan: {out_path} ({len(plan_rows)} rows)")
    print(f"  copy (donor found): {counts['copy']}")
    print(f"  interpolate (no donor within max_lead={args.max_lead}): {counts['interpolate']}")


if __name__ == "__main__":
    main()
