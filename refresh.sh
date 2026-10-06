#!/usr/bin/env bash
# Pull upstream's freshly imported database and rebuild Martin and style.json from the
# same upstream commit, so the SQL functions Martin calls always exist in the database and
# the style matches the tiles.
#
# Upstream's nightly job starts 22:47 UTC and takes a few hours; run after it:
#   0 6 * * * /path/to/trainlog_orm/refresh.sh >> /path/to/trainlog_orm/refresh.log 2>&1
#
# Recreating orm-db means a few seconds of 502s; nginx serves stale tiles through it.
set -euo pipefail
cd "$(dirname "$0")"

echo "== $(date -Is) refresh start"
docker compose pull orm-db
docker compose build --pull martin-orm orm
docker compose up -d --wait orm-db
docker compose run --rm orm-patch
# Martin's pool held connections to the old database container
docker compose up -d --force-recreate martin-orm
docker compose up -d orm
# Drop the previous ~10 GB database image now that nothing uses it
docker image prune -f
echo "== $(date -Is) refresh done"
