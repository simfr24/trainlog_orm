#!/bin/sh
# Renders every overlay tile up to zoom 8 once, through nginx's private port 5001 which always
# re-renders and stores (nginx.conf), so zoomed out maps are served from the cache only.
# Run by refresh.sh after each database pull; takes a while, mostly empty ocean tiles.
set -eu

list=/tmp/tiles.txt
: > "$list"

tiles() { # path minzoom maxzoom [extension]
  z=$2
  while [ "$z" -le "$3" ]; do
    n=$((1 << z)) x=0
    while [ "$x" -lt "$n" ]; do
      y=0
      while [ "$y" -lt "$n" ]; do
        printf 'url = "http://orm:5001/%s/%s/%s/%s%s"\noutput = "/dev/null"\n' "$1" "$z" "$x" "$y" "${4:-}"
        y=$((y + 1))
      done
      x=$((x + 1))
    done
    z=$((z + 1))
  done
}

# RASTER_ONLY=1: just the images, after a change to Trainlog's overlay style
if [ -z "${RASTER_ONLY:-}" ]; then
# Low zoom line sources of the overlay presets (src/openrailwaymap.py in Trainlog)
for source in standard_railway_line_low speed_railway_line_low \
    signals_railway_line_low,signals_railway_line_low_construction \
    electrification_railway_line_low track_railway_line_low operator_railway_line_low; do
  tiles "$source" 0 6
done >> "$list"
# Zoom 7+ lines: the one URL the overlay and Trainlog Rail share
tiles railway_line_high,railway_text_km 7 8 >> "$list"
fi
# The overlay below zoom 6 as images, rendered from the vector tiles above (martin-render),
# so last
for mode in standard speed signals electrification track; do
  for variant in bold thin; do
    tiles "raster/$mode-$variant" 0 5 .png
  done
done >> "$list"

total=$(grep -c '^url' "$list")
echo "$(date -Is) warming $total tiles"
# 6 at a time leaves half the CPU to live traffic. Progress every 1000 tiles (the ETA is rough:
# ocean tiles are instant, cities take seconds), then one line per HTTP status (000: no
# answer), so a run that went nowhere shows
curl --silent --parallel --parallel-max 6 --config "$list" --write-out '%{http_code}\n' \
  | awk -v total="$total" '
      function now(  t) { "date +%s" | getline t; close("date +%s"); return t }
      BEGIN { start = now() }
      { status[$1]++ }
      NR % 1000 == 0 {
        elapsed = now() - start
        printf "%d/%d (%.0f%%), %d min left\n", NR, total, 100 * NR / total, elapsed * (total - NR) / NR / 60
        fflush()
      }
      END { for (s in status) print status[s], s }' || true
echo "$(date -Is) warm done"
