#!/usr/bin/env python3
"""
Stage 3 (execute): materializes the raw_filled/<year> overlay tree from the
Stage 1 ledger + Stage 2 plan. raw/<year> is never written to.

For every (date, hour, lead_group) target:
  - ledger status "ok"          -> symlink to the real file in raw/<year>
  - plan action "copy"          -> build a repaired file with wgrib2, written
                                    for real into raw_filled/<year>
  - plan action "interpolate"   -> not implemented here (none occurred for
                                    WY2018); logged and left absent rather
                                    than silently faked

Only F01/F06 are materialized -- those are the only leads PreprocessHRRR
reads (get_fXX_flist in input.py), so the overlay tree doesn't need the
donor leads (F02-F13) at all.

Usage:
    python execute.py ledger_2018.csv plan_2018.csv --out-base /.../raw_filled
"""
import argparse
import csv
import subprocess
from pathlib import Path

MET_MATCH = "TMP|RH|UGRD|VGRD|DSWRF|DLWRF"
LEAD_NUMBER = {"F01": "01", "F06": "06"}
TARGET_LEAD = {"F01": 1, "F06": 6}


def raw_path(raw_base: Path, year: str, date: str, hour: str, lead_num: str) -> Path:
    ymd = date.replace("-", "")
    return raw_base / year / f"hrrr.{ymd}" / f"hrrr.t{int(hour):02d}z.wrfsfcf{lead_num}.grib2"


def build_met_repair(donor_path: Path, hop: int, target_lead: int, out_path: Path):
    cmd = [
        "wgrib2", str(donor_path),
        "-match", MET_MATCH,
        "-set_date", f"+{hop}hr",
        "-set_ftime", f"{target_lead} hour fcst",
        "-grib_out", str(out_path),
    ]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60)


def build_precip_repair(donor_path: Path, donor_lead: int, hop: int, out_path: Path):
    # F06's target is always "5-6 hour acc fcst" (target_lead fixed at 6); the
    # donor contributes its OWN most-recent 1-hour bucket at its own lead, for
    # both APCP (rain+snow total) and WEASD (snow water-equivalent only).
    donor_bucket = f"{donor_lead - 1}-{donor_lead} hour acc fcst"
    match = f"APCP:surface:{donor_bucket}|WEASD:surface:{donor_bucket}"
    cmd = [
        "wgrib2", str(donor_path),
        "-match", match,
        "-set_date", f"+{hop}hr",
        "-set_ftime", "5-6 hour acc fcst",
        "-grib_out", str(out_path),
    ]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=60)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("ledger")
    ap.add_argument("plan")
    ap.add_argument("--raw-base", default="/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw")
    ap.add_argument("--out-base", default="/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw_filled")
    ap.add_argument("--year", default=None)
    ap.add_argument("--exec-log", default=None)
    args = ap.parse_args()

    ledger_rows = list(csv.DictReader(open(args.ledger)))
    plan_rows = list(csv.DictReader(open(args.plan)))
    plan_by_key = {(r["date"], r["hour"], r["lead_group"]): r for r in plan_rows}

    year = args.year or Path(args.ledger).stem.split("_")[-1]
    raw_base = Path(args.raw_base)
    out_base = Path(args.out_base)
    exec_log_path = Path(args.exec_log) if args.exec_log else Path(f"exec_{year}.csv")

    counts = {"symlink": 0, "copy_ok": 0, "copy_failed": 0, "interpolate_skipped": 0}
    exec_rows = []

    for i, r in enumerate(ledger_rows):
        date, hour, lead_group, status = r["date"], r["hour"], r["lead_group"], r["status"]
        lead_num = LEAD_NUMBER[lead_group]
        out_path = raw_path(out_base, year, date, hour, lead_num)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        if status == "ok":
            src = raw_path(raw_base, year, date, hour, lead_num).resolve()
            if out_path.is_symlink() or out_path.exists():
                out_path.unlink()
            out_path.symlink_to(src)
            counts["symlink"] += 1
            exec_rows.append([date, hour, lead_group, "symlink", "ok", ""])
            continue

        plan = plan_by_key.get((date, hour, lead_group))
        action = plan["action"] if plan else "interpolate"

        if action == "copy":
            hop = int(plan["hop"])
            donor_lead = int(plan["donor_lead"])
            donor_path = Path(plan["donor_path_or_note"])
            if lead_group == "F01":
                res = build_met_repair(donor_path, hop, TARGET_LEAD["F01"], out_path)
            else:
                res = build_precip_repair(donor_path, donor_lead, hop, out_path)
            if res.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0:
                counts["copy_ok"] += 1
                exec_rows.append([date, hour, lead_group, "copy", "ok", f"hop={hop} donor_lead={donor_lead}"])
            else:
                counts["copy_failed"] += 1
                exec_rows.append([date, hour, lead_group, "copy", "failed", res.stderr.strip()[:200]])
        else:
            counts["interpolate_skipped"] += 1
            exec_rows.append([date, hour, lead_group, "interpolate", "skipped", "not implemented"])

        if (i + 1) % 2000 == 0:
            print(f"  ... {i + 1}/{len(ledger_rows)}")

    with open(exec_log_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["date", "hour", "lead_group", "action", "result", "detail"])
        w.writerows(exec_rows)

    print(f"\nWrote execution log: {exec_log_path}")
    for k, v in counts.items():
        print(f"  {k}: {v}")
    print(f"\nOverlay tree: {out_base}")


if __name__ == "__main__":
    main()
