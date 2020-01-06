CREATE FUNCTION check_detector_for_anomaly(checked_detector_id int, anomaly_threshold int default 5) RETURNS VOID AS $$
DECLARE
  it_row record;
  difference NUMERIC;
BEGIN
  FOR it_row IN
    (
      WITH ordered_series AS (
        SELECT detector_id, starttime, count FROM traffic WHERE detector_id=checked_detector_id ORDER BY starttime
        ) SELECT
            detector_id,
            starttime,
            count,
            LAG(count, 1) OVER ( ORDER BY starttime ) previous_series_count
          FROM ordered_series
    )
    LOOP
      difference := (it_row.count - it_row.previous_series_count);
      IF difference > anomaly_threshold THEN
        raise notice 'Noticed anomaly in detector % at: %. Difference between this reading and previous is %', it_row.detector_id, it_row.starttime, difference;
      end IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
