CREATE FUNCTION get_percentile_for_detector(checked_detector_id int, percentile real) RETURNS int AS $$
BEGIN
  RETURN (select percentile_cont(percentile) within group (order by count)
          from traffic WHERE detector_id=checked_detector_id
          group by detector_id);
END;
$$ LANGUAGE plpgsql;

CREATE TYPE neg_pos_outlier_thresholds AS (neg_outlier_threshold real, pos_outlier_threshold real);

CREATE FUNCTION get_neg_pos_outlier_values_for_detector(checked_detector_id int, interquartile_multiplier real default 1.5) RETURNS neg_pos_outlier_thresholds AS $$
DECLARE
  percentile_25 INTEGER;
  percentile_75 INTEGER;
  interquartile_range INTEGER;
  neg_outlier_value_threshold real;
  pos_outlier_value_threshold real;
  result_record neg_pos_outlier_thresholds;
BEGIN
  percentile_25 := (SELECT get_percentile_for_detector(checked_detector_id, 0.25));
  percentile_75 := (SELECT get_percentile_for_detector(checked_detector_id, 0.75));
  interquartile_range := percentile_75 - percentile_25;
  neg_outlier_value_threshold := percentile_25 - interquartile_multiplier*interquartile_range;
  pos_outlier_value_threshold := percentile_75 + interquartile_multiplier*interquartile_range;
  result_record.neg_outlier_threshold = neg_outlier_value_threshold;
  result_record.pos_outlier_threshold = pos_outlier_value_threshold;
  RETURN result_record;
END;
$$ LANGUAGE plpgsql;

