#!/usr/bin/env python3
"""Optionally pre-bundle the FULL OurAirports database into the app.

The app can download this data itself at runtime (Settings → Download full
airport database), so running this script is optional. Run it on a machine
with internet access if you want worldwide airports available offline on
first launch:

    python3 Scripts/build_airport_db.py

It downloads the public-domain OurAirports dataset and rewrites
TailTrack/Resources/airports-starter.json with every open small/medium/large
airport and seaplane base (~60k rows, ~12 MB JSON).
"""
import csv
import io
import json
import os
import urllib.request

URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
OUT = os.path.join(os.path.dirname(__file__), "..", "TailTrack", "Resources", "airports-starter.json")
KEEP = {"small_airport", "medium_airport", "large_airport", "seaplane_base"}


def main():
    print(f"downloading {URL} …")
    with urllib.request.urlopen(URL) as resp:
        text = resp.read().decode("utf-8")

    records = []
    for row in csv.DictReader(io.StringIO(text)):
        if row.get("type") not in KEEP:
            continue
        ident = (row.get("ident") or "").strip()
        try:
            lat = float(row["latitude_deg"])
            lon = float(row["longitude_deg"])
        except (KeyError, ValueError):
            continue
        if not ident:
            continue

        def opt(key):
            v = (row.get(key) or "").strip()
            return v or None

        elev = opt("elevation_ft")
        records.append({
            "ident": ident,
            "name": (row.get("name") or "").strip(),
            "latitude": lat,
            "longitude": lon,
            "elevationFt": int(float(elev)) if elev else None,
            "iata": opt("iata_code"),
            "municipality": opt("municipality"),
            "region": opt("iso_region"),
            "kind": row["type"],
        })

    with open(os.path.abspath(OUT), "w") as f:
        json.dump(records, f, separators=(",", ":"))
    print(f"wrote {len(records)} airports to {os.path.abspath(OUT)}")


if __name__ == "__main__":
    main()
