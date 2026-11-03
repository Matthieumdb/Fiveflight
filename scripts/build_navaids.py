#!/usr/bin/env python3
"""Build Resources/navaids.json: VOR/NDB (OurAirports, public domain) and FAA fixes / VFR
waypoints (FAA ADDS DesignatedPoint layer) around Florida, in Fiveflight's `Airport` Codable format.

Usage: python3 scripts/build_navaids.py [output.json]
A failing source is skipped (the other one is still written); an empty result keeps the old file.
"""
import csv
import io
import json
import os
import sys
import urllib.parse
import urllib.request

OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/navaids.json"
MIN_LAT, MAX_LAT, MIN_LON, MAX_LON = 23.5, 31.8, -88.5, -79.0
ARCGIS = "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services"
UA = {"User-Agent": "Fiveflight-data/1.0"}


def inside(lat, lon):
    return MIN_LAT <= lat <= MAX_LAT and MIN_LON <= lon <= MAX_LON


def get(url, timeout=120):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def navaids():
    out = []
    for url in ("https://davidmegginson.github.io/ourairports-data/navaids.csv",
                "https://ourairports.com/data/navaids.csv"):
        try:
            text = get(url).decode("utf-8", "replace")
            break
        except Exception as e:  # noqa: BLE001
            print(f"navaids: {url} failed: {e}")
    else:
        return out
    for row in csv.DictReader(io.StringIO(text)):
        try:
            lat, lon = float(row["latitude_deg"]), float(row["longitude_deg"])
        except (KeyError, ValueError):
            continue
        if row.get("iso_country") != "US" or not inside(lat, lon):
            continue
        kind = row.get("type", "").upper()
        typ = "ndb" if "NDB" in kind else "vor"
        freq = row.get("frequency_khz") or ""
        try:
            f = float(freq)
            label = f"{f / 1000:.2f} MHz" if typ == "vor" else f"{int(f)} kHz"
        except ValueError:
            label = ""
        name = f"{row.get('name', '').title()} {kind}".strip() + (f" · {label}" if label else "")
        elev = row.get("elevation_ft")
        out.append({"id": row["ident"].strip().upper(), "name": name, "type": typ,
                    "latitude": round(lat, 5), "longitude": round(lon, 5),
                    "elevationFt": int(float(elev)) if elev else None})
    print(f"navaids: {len(out)}")
    return out


def pick(props, *names):
    low = {k.lower(): v for k, v in props.items()}
    for n in names:
        v = low.get(n.lower())
        if v not in (None, ""):
            return v
    return None


def fixes():
    for layer in ("DesignatedPoint", "Designated_Points", "DesignatedPoints"):
        feats, offset = [], 0
        try:
            while True:
                params = {"where": "1=1", "geometry": f"{MIN_LON},{MIN_LAT},{MAX_LON},{MAX_LAT}",
                          "geometryType": "esriGeometryEnvelope", "inSR": "4326",
                          "spatialRel": "esriSpatialRelIntersects", "outFields": "*", "outSR": "4326",
                          "f": "geojson", "resultOffset": str(offset), "resultRecordCount": "2000"}
                data = json.loads(get(f"{ARCGIS}/{layer}/FeatureServer/0/query?{urllib.parse.urlencode(params)}"))
                if "error" in data:
                    raise RuntimeError(data["error"])
                page = data.get("features", [])
                feats += page
                exceeded = data.get("exceededTransferLimit") or data.get("properties", {}).get("exceededTransferLimit")
                if not page or not exceeded:
                    break
                offset += len(page)
        except Exception as e:  # noqa: BLE001
            print(f"fixes: layer {layer} failed: {e}")
            continue
        if feats:
            print(f"fixes: layer {layer}, {len(feats)} features, fields {sorted(feats[0].get('properties', {}).keys())}")
        out = []
        for f in feats:
            g = f.get("geometry") or {}
            if g.get("type") != "Point":
                continue
            lon, lat = g["coordinates"][:2]
            p = f.get("properties") or {}
            ident = pick(p, "IDENT_TXT", "IDENT", "FIX_ID", "NAME_TXT", "NAME")
            if not ident or not inside(lat, lon):
                continue
            code = str(pick(p, "TYPE_CODE", "TYPE", "USE_CODE") or "").upper()
            typ = "vfr_wp" if code.startswith("VFR") or str(ident).upper().startswith("VP") else "fix"
            label = "Point VFR" if typ == "vfr_wp" else "Fix"
            out.append({"id": str(ident).strip().upper(), "name": f"{label} {str(ident).strip().upper()}",
                        "type": typ, "latitude": round(lat, 5), "longitude": round(lon, 5)})
        if out:
            print(f"fixes: {len(out)}")
            return out
    return []


def main():
    items = navaids() + fixes()
    seen, unique = set(), []
    for i in items:
        key = (i["id"], i["type"])
        if key not in seen:
            seen.add(key)
            unique.append(i)
    if not unique:
        print("no data, keeping the existing file")
        return
    if os.path.exists(OUT) and len(unique) < 50:
        print("suspiciously small result, keeping the existing file")
        return
    unique.sort(key=lambda i: (i["type"], i["id"]))
    with open(OUT, "w") as f:
        json.dump(unique, f, separators=(",", ":"))
    print(f"wrote {len(unique)} points to {OUT}")


if __name__ == "__main__":
    main()
