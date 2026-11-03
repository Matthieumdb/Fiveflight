"""Builds Resources/obstacles_fl.json from the FAA Digital Obstacle File (DAILY_DOF_DAT.ZIP).

Usage: python3 scripts/build_obstacles.py DOF.DAT Resources/obstacles_fl.json
Keeps Florida obstacles 200 ft AGL or taller as [lat, lon, amsl_ft, agl_ft] (rounded).
"""
import json, sys

def deg(d, m, s, hemi):
    v = int(d) + int(m) / 60 + float(s) / 3600
    return -v if hemi in "SW" else v

out = []
with open(sys.argv[1], encoding="latin-1") as f:
    for line in f:
        if len(line) < 100 or line[15:17] != "FL":
            continue
        lat = deg(line[35:37], line[38:40], line[41:46], line[46])
        lon = deg(line[48:51], line[52:54], line[55:60], line[60])
        agl, amsl = int(line[83:88]), int(line[89:94])
        if agl >= 200:
            out.append([round(lat, 4), round(lon, 4), amsl, agl])
json.dump(out, open(sys.argv[2], "w"), separators=(",", ":"))
print(len(out), "obstacles")
