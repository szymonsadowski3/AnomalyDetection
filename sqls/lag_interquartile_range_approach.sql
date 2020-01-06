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

-- check query
SELECT traffic_diff_, COUNT(traffic_diff_) FROM (SELECT traffic_diff_ FROM get_analytic_window_traffic_difference(8)) wtd GROUP BY traffic_diff_;
--

CREATE OR REPLACE FUNCTION get_percentile_for_traffic_difference(checked_detector_id int, percentile real) RETURNS int AS $$
BEGIN
  RETURN (select percentile_cont(percentile) within group (order by traffic_diff_)
          from (SELECT traffic_diff_ FROM get_analytic_window_traffic_difference(checked_detector_id)) wtd);
END;
$$ LANGUAGE plpgsql;


CREATE TYPE neg_pos_outlier_thresholds AS (neg_outlier_threshold real, pos_outlier_threshold real);

CREATE FUNCTION get_neg_pos_outlier_values_for_traffic_difference(checked_detector_id int, interquartile_multiplier real default 1.5) RETURNS neg_pos_outlier_thresholds AS $$
DECLARE
  percentile_25 INTEGER;
  percentile_75 INTEGER;
  interquartile_range INTEGER;
  neg_outlier_value_threshold real;
  pos_outlier_value_threshold real;
  result_record neg_pos_outlier_thresholds;
BEGIN
  percentile_25 := (SELECT get_percentile_for_traffic_difference(checked_detector_id, 0.25));
  percentile_75 := (SELECT get_percentile_for_traffic_difference(checked_detector_id, 0.75));
  interquartile_range := percentile_75 - percentile_25;
  neg_outlier_value_threshold := percentile_25 - interquartile_multiplier*interquartile_range;
  pos_outlier_value_threshold := percentile_75 + interquartile_multiplier*interquartile_range;
  result_record.neg_outlier_threshold = neg_outlier_value_threshold;
  result_record.pos_outlier_threshold = pos_outlier_value_threshold;
  RETURN result_record;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION check_traffic_diff_for_anomaly(checked_detector_id int) RETURNS VOID AS $$
DECLARE
  it_row record;
  thresholds neg_pos_outlier_thresholds;
BEGIN
  thresholds := get_neg_pos_outlier_values_for_traffic_difference(checked_detector_id);

  FOR it_row IN
    (SELECT * FROM get_analytic_window_traffic_difference(checked_detector_id))
    LOOP
      IF it_row.traffic_diff_ > thresholds.pos_outlier_threshold THEN
        raise notice 'Noticed POSITIVE OUTLIER anomaly in detector % at: %. Difference between this reading and previous is %', checked_detector_id, it_row.starttime_, it_row.traffic_diff_;
      ELSIF it_row.traffic_diff_ <= thresholds.neg_outlier_threshold THEN
        raise notice 'Noticed NEGATIVE OUTLIER anomaly in detector % at: %. Difference between this reading and previous is %', checked_detector_id, it_row.starttime_, it_row.traffic_diff_;
      end IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

