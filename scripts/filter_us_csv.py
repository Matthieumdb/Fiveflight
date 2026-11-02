#!/usr/bin/env python3
"""Reduce the OurAirports CSVs in Resources/ to US airports only.

Usage: python3 scripts/filter_us_csv.py [Resources]
Fiveflight is a US VFR EFB, so shipping worldwide data only costs ~12 MB of IPA
and launch time. Closed airports are dropped too.
"""
import csv
import sys
from pathlib import Path

res = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources")


def rewrite(name, keep):
    path = res / name
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = [r for r in reader if keep(dict(zip(header, r)))]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)
    return len(rows)


idents = set()


def keep_airport(r):
    if r["iso_country"] != "US" or r["type"] == "closed":
        return False
    idents.add(r["ident"])
    return True


n = rewrite("airports.csv", keep_airport)
m = rewrite("runways.csv", lambda r: r["airport_ident"] in idents)
k = rewrite("airport-frequencies.csv", lambda r: r["airport_ident"] in idents)
print(f"airports={n} runways={m} frequencies={k}")
