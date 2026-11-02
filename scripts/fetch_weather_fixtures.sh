#!/usr/bin/env bash
# Captures real aviationweather.gov responses as test fixtures, so the app's
# decoders are tested against the live data format (not a guessed one).
set -u
OUT="${1:-Tests/Fixtures}"
mkdir -p "$OUT"
API="https://aviationweather.gov/api/data"
IDS="KFPR,KVRB,KMIA,KORL,KTPA,KJAX,KPBI,KSUA"
fetch() { # name url
  code=$(curl -sS -m 60 -A "Fiveflight-fixtures/1.0" -o "$OUT/$1" -w "%{http_code}" "$2" || echo "000")
  echo "$1 <- $2 : HTTP $code ($(wc -c < "$OUT/$1" 2>/dev/null || echo 0) bytes)"
}
fetch metar.json      "$API/metar?ids=$IDS&format=json"
fetch taf.json        "$API/taf?ids=$IDS&format=json"
fetch windtemp.txt    "$API/windtemp?region=all&level=low&fcst=06"
fetch pirep.json      "$API/pirep?format=json&age=6&bbox=24,-88,31.5,-79"
fetch pirep_id.json   "$API/pirep?format=json&age=6&id=KORL&distance=300"
fetch airsigmet.json  "$API/airsigmet?format=json"
fetch gairmet.json    "$API/gairmet?format=json"
# Keep fixtures small: trim big JSON arrays to the first 40 entries.
for f in "$OUT"/*.json; do
  python3 - "$f" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception:
    sys.exit(0)
if isinstance(d, list) and len(d) > 40:
    json.dump(d[:40], open(p, "w"), indent=1)
PY
done
exit 0
