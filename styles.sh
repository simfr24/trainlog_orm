#!/bin/sh
# Fetches the overlay render styles from Trainlog (src/openrailwaymap.py render_style) for
# martin-render, pointing their tiles at our nginx inside the network. Run by style-init.
set -eu
for mode in standard speed signals electrification track; do
  for variant in bold thin; do
    query=render
    [ "$variant" = bold ] && query="render&bold"
    curl -fsS --retry 5 --retry-delay 3 "$TRAINLOG_URL/getORMStyle/$mode.json?$query" \
      | sed "s#$TILES_URL#http://orm:5000#g" > "/styles/$mode-$variant.json"
  done
done
echo "styles written: $(ls /styles | tr '\n' ' ')"
