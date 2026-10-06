#!/bin/sh
# Fetches the overlay render styles from Trainlog (src/openrailwaymap.py render_style) for
# martin-render, pointing their tiles at our nginx inside the network. Run by style-init.
set -eu
for mode in standard speed signals electrification track; do
  for variant in bold thin; do
    query=render
    [ "$variant" = bold ] && query="render&bold"
    # Not piped: a failed fetch must fail the run, not leave an empty style behind.
    # TRAINLOG_HOST: Trainlog only answers its own host names (local runs reach it by another)
    curl -fsS --retry 5 --retry-delay 3 ${TRAINLOG_HOST:+-H "Host: $TRAINLOG_HOST"} \
      -o /tmp/style.json "$TRAINLOG_URL/getORMStyle/$mode.json?$query"
    sed "s#$TILES_URL#http://orm:5000#g" /tmp/style.json > "/styles/$mode-$variant.json"
  done
done
echo "styles written: $(ls /styles | tr '\n' ' ')"
