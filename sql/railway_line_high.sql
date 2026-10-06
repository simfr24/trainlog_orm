-- Replaces upstream's railway_line_high (import/sql/tile_views.sql) after every database pull.
-- Planned and former lines are mapped as many short ways, and MapLibre restarts a dash pattern
-- at the start of every feature, so their dashes came out ragged. Here ways that are not in
-- service and share every attribute the style reads are merged into one line per stretch.
-- Lines in service are left as upstream builds them.
--
-- Also shows narrow gauge main lines from zoom 5 rather than 10: networks like Corsica's are
-- metre gauge and mostly carry no usage tag, so upstream's low zoom rules skipped them.
--
-- A copy of upstream's function: when upstream changes its columns or zoom rules, bring them
-- over here too, or the tiles silently keep the old ones.
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
      way && ST_TileEnvelope(z, x, y)
      -- conditionally include features based on zoom level
      AND CASE
        -- Zooms < 7 are handled in the low zoom tiles, which leave out narrow gauge: add it here
        -- (Martin serves this function from zoom 5, see docker-compose.yml)
        WHEN z < 7 THEN
          state = 'present'
            AND service IS NULL
            AND feature = 'narrow_gauge' AND (usage IS NULL OR usage IN ('main', 'branch'))
        WHEN z < 8 THEN
          state = 'present'
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch')
                OR (feature = 'narrow_gauge' AND (usage IS NULL OR usage IN ('main', 'branch')))
            )
        WHEN z < 9 THEN
          state IN ('present', 'construction', 'proposed')
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch')
                OR (feature = 'narrow_gauge' AND (usage IS NULL OR usage IN ('main', 'branch')))
            )
        WHEN z < 10 THEN
          state IN ('present', 'construction', 'proposed')
            AND service IS NULL
            AND (
              feature IN ('rail', 'ferry') AND usage IN ('main', 'branch', 'industrial')
                OR (feature IN ('light_rail', 'narrow_gauge') AND usage IN ('main', 'branch'))
                OR (feature = 'narrow_gauge' AND usage IS NULL)
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
