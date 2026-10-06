-- Replaces upstream's railway_line_high (import/sql/tile_views.sql) after every database pull.
-- Planned and former lines are mapped as many short ways, and MapLibre restarts a dash pattern
-- at the start of every feature, so their dashes came out ragged. Here ways that are not in
-- service and share every attribute the style reads are merged into one line per stretch.
-- Lines in service are left as upstream builds them.
--
-- Also shows narrow gauge networks from zoom 5 rather than 10: networks like Corsica's are
-- metre gauge and mostly carry no usage tag, so upstream's low zoom rules skipped them.
--
-- A copy of upstream's function: when upstream changes its columns or zoom rules, bring them
-- over here too, or the tiles silently keep the old ones.

-- Narrow gauge shown below zoom 10. Short isolated lines, rack and tourist railways mostly, came
-- out as scattered dots, so only connected networks of at least 30 km are kept (way_length is in
-- Web Mercator metres; tagged or not, so a line with mixed usage tags isn't split). Built once per
-- database pull: worked out per tile, it saturated the database
CREATE TABLE IF NOT EXISTS trainlog_narrow_gauge AS
  SELECT
      id, way, way_length,
      layer, rank, feature, state, usage, service, highspeed, preserved, tunnel, bridge, name, ref,
      track_ref, track_class, preferred_direction, maxspeed, speed_label, train_protection_rank,
      train_protection, train_protection_construction_rank, train_protection_construction,
      electrification_state, voltage, frequency, maximum_current, future_voltage, future_frequency,
      future_maximum_current, gauges, gaugeint0, gauge0, gaugeint1, gauge1, gaugeint2, gauge2,
      loading_gauge, operator, operator_color, operator_bright, primary_operator, owner, route_count,
      passenger_lines, rack, radio
  FROM railway_line_view
  WITH NO DATA;
CREATE INDEX IF NOT EXISTS trainlog_narrow_gauge_way ON trainlog_narrow_gauge USING gist (way);

BEGIN;
DELETE FROM trainlog_narrow_gauge;
INSERT INTO trainlog_narrow_gauge
  WITH ways AS (
    SELECT id, way_length, ST_ClusterDBSCAN(way, eps := 50, minpoints := 1) OVER () AS network
    FROM railway_line
    WHERE feature = 'narrow_gauge' AND state = 'present' AND service IS NULL
  )
  SELECT
      id, way, way_length,
      layer, rank, feature, state, usage, service, highspeed, preserved, tunnel, bridge, name, ref,
      track_ref, track_class, preferred_direction, maxspeed, speed_label, train_protection_rank,
      train_protection, train_protection_construction_rank, train_protection_construction,
      electrification_state, voltage, frequency, maximum_current, future_voltage, future_frequency,
      future_maximum_current, gauges, gaugeint0, gauge0, gaugeint1, gauge1, gaugeint2, gauge2,
      loading_gauge, operator, operator_color, operator_bright, primary_operator, owner, route_count,
      passenger_lines, rack, radio
  FROM railway_line_view
  WHERE id IN (
      SELECT id FROM ways
      WHERE network IN (SELECT network FROM ways GROUP BY network HAVING sum(way_length) >= 30000)
    )
    AND (usage IS NULL OR usage IN ('main', 'branch'));
COMMIT;

CREATE OR REPLACE FUNCTION railway_line_high(z integer, x integer, y integer)
  RETURNS bytea
  LANGUAGE SQL
  IMMUTABLE
  STRICT
  PARALLEL SAFE
RETURN (
  WITH lines AS (
    SELECT
      id, way, way_length,
      layer, rank, feature, state, usage, service, highspeed, preserved, tunnel, bridge, name, ref,
      track_ref, track_class, preferred_direction, maxspeed, speed_label, train_protection_rank,
      train_protection, train_protection_construction_rank, train_protection_construction,
      electrification_state, voltage, frequency, maximum_current, future_voltage, future_frequency,
      future_maximum_current, gauges, gaugeint0, gauge0, gaugeint1, gauge1, gaugeint2, gauge2,
      loading_gauge, operator, operator_color, operator_bright, primary_operator, owner, route_count,
      passenger_lines, rack, radio
    FROM railway_line_view
    WHERE
      -- Martin serves this function from zoom 5 (docker-compose.yml), for the narrow gauge below
      z >= 7
      AND way && ST_TileEnvelope(z, x, y)
      -- conditionally include features based on zoom level
      AND CASE
        -- Zooms < 7 are handled in the low zoom tiles
        WHEN z < 8 THEN
          state = 'present'
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch')
            )
        WHEN z < 9 THEN
          state IN ('present', 'construction', 'proposed')
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch')
            )
        WHEN z < 10 THEN
          state IN ('present', 'construction', 'proposed')
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch', 'industrial')
                OR (feature = 'light_rail' AND usage IN ('main', 'branch'))
            )
        WHEN z < 11 THEN
          state IN ('present', 'construction', 'proposed')
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry', 'narrow_gauge', 'light_rail', 'monorail', 'subway', 'tram')
            )
        WHEN z < 12 THEN
          state IN ('present', 'construction', 'proposed', 'disused')
            AND (service IS NULL OR service IN ('spur', 'yard'))
            AND (
              feature IN ('rail', 'ferry', 'narrow_gauge', 'light_rail')
                OR (feature IN ('monorail', 'subway', 'tram') AND service IS NULL)
            )
        ELSE
          true
      END
    UNION ALL
    SELECT * FROM trainlog_narrow_gauge
    WHERE z < 10 AND way && ST_TileEnvelope(z, x, y)
  ),
  merged AS (
    SELECT * FROM lines WHERE state = 'present'
    UNION ALL
    SELECT
      min(id), ST_LineMerge(ST_Collect(way)), sum(way_length),
      -- Bridges and tunnels are separate ways: splitting on them left a gap, and a restart, at each
      NULL::integer, rank, feature, state, usage, service, highspeed, preserved, false, false, name, ref,
      track_ref, track_class, preferred_direction, maxspeed, speed_label, train_protection_rank,
      train_protection, train_protection_construction_rank, train_protection_construction,
      electrification_state, voltage, frequency, maximum_current, future_voltage, future_frequency,
      future_maximum_current, gauges, gaugeint0, gauge0, gaugeint1, gauge1, gaugeint2, gauge2,
      loading_gauge, operator, operator_color, operator_bright, primary_operator, owner, route_count,
      passenger_lines, rack, radio
    FROM lines
    WHERE state IS DISTINCT FROM 'present'
    GROUP BY
      rank, feature, state, usage, service, highspeed, preserved, name, ref,
      track_ref, track_class, preferred_direction, maxspeed, speed_label, train_protection_rank,
      train_protection, train_protection_construction_rank, train_protection_construction,
      electrification_state, voltage, frequency, maximum_current, future_voltage, future_frequency,
      future_maximum_current, gauges, gaugeint0, gauge0, gaugeint1, gauge1, gaugeint2, gauge2,
      loading_gauge, operator, operator_color, operator_bright, primary_operator, owner, route_count,
      passenger_lines, rack, radio
  ),
  -- Double track proposals are mapped as two parallel ways, which merge into two parts lying on
  -- top of each other at these zooms, their dashes out of step. Keep only the longest of the
  -- parts within 2 pixels of each other
  parts AS (
    SELECT id, part.geom, part.path, ST_Length(part.geom) AS length
    FROM merged, ST_Dump(way) AS part
    WHERE state IS DISTINCT FROM 'present'
  ),
  kept AS (
    SELECT id, ST_Collect(geom) AS way
    FROM parts a
    WHERE NOT EXISTS (
      SELECT 1 FROM parts b
      WHERE b.id = a.id
        AND (b.length, b.path) > (a.length, a.path)
        AND ST_Covers(ST_Buffer(b.geom, 2 * 40075016.68 / (256 * 2 ^ z)), a.geom)
    )
    GROUP BY id
  )
  SELECT
    ST_AsMVT(tile, 'railway_line_high', 4096, 'way')
  FROM (
    SELECT
      id,
      ST_AsMVTGeom(coalesce(kept.way, merged.way), ST_TileEnvelope(z, x, y), extent => 4096, buffer => 64, clip_geom => true) AS way,
      way_length,
      feature,
      state,
      usage,
      service,
      highspeed,
      preserved,
      tunnel,
      bridge,
      name,
      ref,
      track_ref,
      track_class,
      preferred_direction,
      rank,
      maxspeed,
      speed_label,
      train_protection_rank,
      train_protection[1] as train_protection0,
      train_protection[2] as train_protection1,
      train_protection[3] as train_protection2,
      train_protection_construction_rank,
      train_protection_construction,
      electrification_state,
      voltage,
      frequency,
      maximum_current,
      future_voltage,
      future_frequency,
      future_maximum_current,
      array_to_string(gauges, ', ') as gauges,
      gaugeint0,
      gauge0,
      gaugeint1,
      gauge1,
      gaugeint2,
      gauge2,
      loading_gauge,
      operator,
      operator_color,
      operator_bright,
      primary_operator,
      owner,
      route_count,
      passenger_lines,
      rack,
      radio
    FROM merged
    LEFT JOIN kept USING (id)
    ORDER by
      coalesce(layer, 0),
      rank NULLS LAST,
      maxspeed NULLS FIRST
  ) as tile
  WHERE way IS NOT NULL
);
