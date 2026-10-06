# trainlog_orm

Self-hosted [OpenRailwayMap](https://github.com/hiddewie/OpenRailwayMap-vector) vector
tiles for Trainlog's OpenRailwayMap map overlay.

openrailwaymap.app rate-limited Trainlog, and its
[usage policy](https://github.com/hiddewie/OpenRailwayMap-vector/blob/master/USAGE.md) only
covers apps usable without registration, which the overlay isn't. So we serve the tiles
ourselves.

No OSM import happens here. Upstream's nightly GitHub Actions job imports the whole planet
and publishes the finished PostGIS database as a public image
(`ghcr.io/hiddewie/openrailwaymap-import-db`). This repo pulls that image, builds Martin from
upstream's own `martin.Dockerfile` and puts an nginx cache in front, which also serves
upstream's `style.json` built from the same commit. Nothing is fetched from
openrailwaymap.app at runtime.

| Container | What | Network |
|---|---|---|
| `orm-db` | upstream's imported database (~2.3 GB compressed; data is inside the image) | private |
| `martin-orm` | upstream's Martin build, rendering tiles from SQL functions in the database | private |
| `orm` | nginx tile cache (1 day, stale served while the database restarts) and `/style.json`, on port 5000 | private + `trainlog_network` |

## Running

```
make up
```

Then expose it through the `services_proxy` nginx: add a line to `nginx.conf` in the infra
repo, next to `train-gh`:

```
if ($service = "orm") { set $target "orm"; set $port 5000; }
```

It's then reachable at `orm.srv.trainlog.me`. Point Trainlog at it in `config.yaml` and
restart the app:

```yaml
openrailwaymap:
  tiles_url: https://orm.srv.trainlog.me
```

Tile paths are the same as upstream's (e.g. `/railway_line_high,railway_text_km/{z}/{x}/{y}`).
Trainlog fetches `{tiles_url}/style.json` once a day and rewrites its relative sources to
`tiles_url`.

## Patched tile function

`sql/railway_line_high.sql` replaces upstream's `railway_line_high` with a copy that merges
ways not in service (proposed, construction, disused…) into one line per stretch, so their
dash patterns don't restart on every OSM way, and keeps one of the parallel ways of double
track proposals. The one-shot `orm-patch` service applies it
after each database pull (`make up`, `refresh.sh`). It is a copy: when upstream changes
`railway_line_high` in `import/sql/tile_views.sql`, port the change.

## Speed

The database gets enough memory to sit entirely in RAM, and `sql/prewarm.sql` loads it there
after each pull. `warm.sh` (`make warm`, also run by `refresh.sh`) then renders every overlay
tile up to zoom 8 into the nginx cache, through a private port that always re-renders, so
zoomed out maps are served from memory only.

## Overlay images below zoom 6

Below zoom 6 Trainlog shows the overlay as images: upstream's low zoom vector tiles are slow to
decode, and a stretched vector tile turns into a staircase while zooming in. `style-init`
fetches Trainlog's render styles (`/getORMStyle/<mode>.json?render`), `martin-render` draws
them, and nginx serves and caches them at `/raster/<mode>/{z}/{x}/{y}.png`
(zoom 0-5 only). The warm renders them all. After deploying a Trainlog change to the overlay
style, refresh them:

```
docker compose up -d --force-recreate style-init martin-render
RASTER_ONLY=1 docker compose run --rm warm
```

## Refreshing

Upstream rebuilds the database nightly from 22:47 UTC. `refresh.sh` (or `make refresh`) pulls
it, rebuilds Martin and `style.json` from the same upstream commit so Martin's SQL functions
exist in the database and the style matches the tiles,
recreates both and prunes the old image. Run it from cron after upstream finishes:

```
0 6 * * * /path/to/trainlog_orm/refresh.sh >> /path/to/trainlog_orm/refresh.log 2>&1
```

During the swap the database is down for a few seconds; nginx keeps serving cached tiles.

## Resources

- Disk: the database image unpacks to roughly 10 GB (not yet measured), and two copies exist
  during a refresh until the prune. The nginx cache is capped at 10 GB.
- Memory: `orm-db` is capped at 3 GB (upstream tunes `shared_buffers` to 1 GB), `martin-orm`
  at 1 GB, `orm` at 256 MB.
