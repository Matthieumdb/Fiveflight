#!/usr/bin/env python3
"""Build Resources/airspace_snapshot.json from the FAA's official ADDS ArcGIS layers.

Usage: python3 scripts/build_airspace_snapshot.py [output.json]

Sources (FAA Aeronautical Data Delivery Service, public, no key):
  Class_Airspace        -> Class B, C, D and Class E surface areas (E2)
  Special_Use_Airspace  -> Restricted, Prohibited, MOA, Warning, Alert areas
Only features intersecting Florida are kept. Polygons are lightly simplified
(maxAllowableOffset ~ 100 m) to keep the app bundle small.
The output matches Fiveflight's `Airspace` Codable format.
"""
import json
import sys
import urllib.parse
import urllib.request

BASE = "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services"
LAYERS = {"class": f"{BASE}/Class_Airspace/FeatureServer/0", "sua": f"{BASE}/Special_Use_Airspace/FeatureServer/0"}
FLORIDA = "-87.7,24.3,-79.8,31.1"
OUT = sys.argv[1] if len(sys.argv) > 1 else "Resources/airspace_snapshot.json"


def query(layer):
    feats, offset = [], 0
    while True:
        params = {
            "where": "1=1", "geometry": FLORIDA, "geometryType": "esriGeometryEnvelope",
            "inSR": "4326", "spatialRel": "esriSpatialRelIntersects", "outFields": "*",
            "outSR": "4326", "f": "geojson", "maxAllowableOffset": "0.001", "geometryPrecision": "5",
            "resultOffset": str(offset), "resultRecordCount": "1000",
        }
        url = f"{layer}/query?{urllib.parse.urlencode(params)}"
        with urllib.request.urlopen(url, timeout=120) as r:
            data = json.load(r)
        if "error" in data:
            raise RuntimeError(f"{layer}: {data['error']}")
        page = data.get("features", [])
        feats += page
        exceeded = data.get("exceededTransferLimit") or data.get("properties", {}).get("exceededTransferLimit")
        if not page or not exceeded:
            return feats
        offset += len(page)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def altitude(props, prefix, default):
    """FAA ADDS altitudes: *_VAL + *_UOM (FT/FL) + *_CODE (SFC, MSL, AGL...). -9998 means 'below FL180'."""
    val = num(props.get(f"{prefix}_VAL"))
    uom = str(props.get(f"{prefix}_UOM") or "").upper()
    code = str(props.get(f"{prefix}_CODE") or "").upper()
    if code == "SFC" or val is None:
        return default if val is None else 0
    if val < 0:
        return 17999
    return int(val * 100) if uom == "FL" else int(val)


def rings(geom):
    if not geom:
        return []
    if geom["type"] == "Polygon":
        polys = [geom["coordinates"]]
    elif geom["type"] == "MultiPolygon":
        polys = geom["coordinates"]
    else:
        return []
    # Outer ring of each polygon only (the app draws filled outlines).
    return [[{"latitude": round(p[1], 5), "longitude": round(p[0], 5)} for p in poly[0]] for poly in polys if poly]


SUA_TYPES = {"R": "RESTRICTED", "P": "PROHIBITED", "MOA": "MOA", "M": "MOA", "W": "WARNING", "A": "ALERT",
             "D": "WARNING", "NSA": "NATIONAL_SECURITY"}


def main():
    out, seen = [], set()
    class_feats = query(LAYERS["class"])
    if class_feats:
        print("Class_Airspace fields:", sorted(class_feats[0]["properties"].keys()))
        print("Class_Airspace sample:", json.dumps(class_feats[0]["properties"])[:800])
    for f in class_feats:
        p = f["properties"]
        cls = str(p.get("CLASS") or "").strip().upper()
        local = str(p.get("LOCAL_TYPE") or "").upper()
        if cls in ("B", "C", "D"):
            typ = {"classAirspace": cls}
        elif local == "CLASS_E2":
            typ = {"classESurface": True}
        else:
            continue
        polys = rings(f.get("geometry"))
        if not polys:
            continue
        ident = str(p.get("IDENT") or p.get("ICAO_ID") or "")
        oid = p.get("OBJECTID") or p.get("GLOBAL_ID") or len(out)
        aid = f"{ident or 'CLASS'}_{cls or 'E2'}_{oid}"
        if aid in seen:
            continue
        seen.add(aid)
        out.append({
            "id": aid, "name": str(p.get("NAME") or ident).strip(), "type": typ, "polygons": polys,
            "floor": altitude(p, "LOWER", 0), "ceiling": altitude(p, "UPPER", 17999),
            "controllingAgency": None, "frequency": None, "isActive": True, "schedule": p.get("WKHR_RMK") or None,
        })

    sua_feats = query(LAYERS["sua"])
    if sua_feats:
        print("Special_Use_Airspace fields:", sorted(sua_feats[0]["properties"].keys()))
        print("Special_Use_Airspace sample:", json.dumps(sua_feats[0]["properties"])[:800])
    for f in sua_feats:
        p = f["properties"]
        code = str(p.get("TYPE_CODE") or "").strip().upper()
        sua = SUA_TYPES.get(code)
        if not sua:
            continue
        polys = rings(f.get("geometry"))
        if not polys:
            continue
        name = str(p.get("NAME") or code).strip()
        aid = f"SUA_{name.replace(' ', '_')}_{p.get('OBJECTID') or len(out)}"
        if aid in seen:
            continue
        seen.add(aid)
        out.append({
            "id": aid, "name": name, "type": {"sua": sua}, "polygons": polys,
            "floor": altitude(p, "LOWER", 0), "ceiling": altitude(p, "UPPER", 17999),
            "controllingAgency": p.get("CONT_AGENT") or None, "frequency": None, "isActive": True,
            "schedule": p.get("TIMESOFUSE") or None,
        })

    counts = {}
    for a in out:
        k = json.dumps(a["type"])
        counts[k] = counts.get(k, 0) + 1
    print("Kept:", len(out), counts)
    if len(out) < 20:
        sys.exit(f"Only {len(out)} airspaces kept, refusing to overwrite {OUT}")
    with open(OUT, "w") as fh:
        json.dump(out, fh, separators=(",", ":"))
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
