#!/bin/sh
# Renders every overlay tile up to zoom 8 once, through nginx's private port 5001 which always
# re-renders and stores (nginx.conf), so zoomed out maps are served from the cache only.
# Run by refresh.sh after each database pull; takes a while, mostly empty ocean tiles.
set -eu

list=/tmp/tiles.txt
: > "$list"

tiles() { # source minzoom maxzoom
  z=$2
  while [ "$z" -le "$3" ]; do
    n=$((1 << z)) x=0
    while [ "$x" -lt "$n" ]; do
      y=0
      while [ "$y" -lt "$n" ]; do
        printf 'url = "http://orm:5001/%s/%s/%s/%s"\noutput = "/dev/null"\n' "$1" "$z" "$x" "$y"
        y=$((y + 1))
      done
      x=$((x + 1))
    done
    z=$((z + 1))
  done
}

# Low zoom line sources of the overlay presets (src/openrailwaymap.py in Trainlog)
for source in standard_railway_line_low speed_railway_line_low \
    signals_railway_line_low,signals_railway_line_low_construction \
    electrification_railway_line_low track_railway_line_low operator_railway_line_low; do
  tiles "$source" 0 6
done >> "$list"
# Zoom 7+ lines: the one URL the overlay and Trainlog Rail share
tiles railway_line_high,railway_text_km 7 8 >> "$list"

echo "$(date -Is) warming $(grep -c '^url' "$list") tiles"
# One line per HTTP status (000: no answer), so a run that went nowhere shows
# 6 at a time leaves half the CPU to live traffic
curl --silent --parallel --parallel-max 6 --config "$list" --write-out '%{http_code}\n' | sort | uniq -c || true
echo "$(date -Is) warm done"
