CREATE FUNCTION get_analytic_window_traffic_difference(checked_detector_id int)
  RETURNS TABLE(starttime_ timestamp, count_ smallint, traffic_diff_ smallint) AS $$
BEGIN
  RETURN QUERY (
    WITH ordered_series AS (
      SELECT starttime, count FROM traffic WHERE detector_id=checked_detector_id ORDER BY starttime
      ) SELECT
          starttime,
          count,
          ABS(count - (LAG(count, 1) OVER ( ORDER BY starttime ))) traffic_diff
        FROM ordered_series
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_percentile_for_traffic_difference(checked_detector_id int, percentile real) RETURNS int AS $$
BEGIN
  RETURN (select percentile_cont(percentile) within group (order by traffic_diff_)
          from (SELECT traffic_diff_ FROM get_analytic_window_traffic_difference(checked_detector_id)) wtd);
END;
$$ LANGUAGE plpgsql;



CREATE TYPE neg_pos_outlier_thresholds AS (neg_outlier_threshold real, pos_outlier_threshold real);


