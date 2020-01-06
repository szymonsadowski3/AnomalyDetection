CREATE OR REPLACE VIEW lag_analytic_window AS (
  WITH ordered_series AS (
    SELECT starttime, count FROM traffic_extract ORDER BY starttime
    ) SELECT
        starttime,
        count,
        LAG(count, 1) OVER ( ORDER BY starttime ) previous_series_count
      FROM ordered_series
);


DO $$
  DECLARE
    it_row record;
    ANOMALY_THRESHOLD CONSTANT NUMERIC := 5;
  BEGIN
    FOR it_row IN
      SELECT * FROM lag_analytic_window
      LOOP
        IF (it_row.count - it_row.previous_series_count) > ANOMALY_THRESHOLD THEN
          raise notice 'Noticed anomaly at: %. Difference between this reading and previous is %', it_row.starttime, (it_row.count - it_row.previous_series_count);
        end IF;
      END LOOP;
  END $$;


CREATE FUNCTION get_percentile_for_detector(checked_detector_id int, percentile real) RETURNS int AS $$
BEGIN
  RETURN (select percentile_cont(percentile) within group (order by count)
          from traffic WHERE detector_id=checked_detector_id
          group by detector_id);
END;
$$ LANGUAGE plpgsql;

