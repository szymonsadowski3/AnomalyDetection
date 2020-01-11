DROP FUNCTION get_analytic_window_traffic_difference(checked_detector_id int);
DROP FUNCTION linear_regression_3point(first_pt int, second_pt int, third_pt int);
DROP FUNCTION check_traffic_diff_for_anomaly(checked_detector_id int, interquartile_multiplier real);

CREATE TYPE slope_intercept_r2_coefficient AS (slope float8, intercept float8, r2_coefficient float8);

CREATE OR REPLACE FUNCTION linear_regression_3point(first_pt int, second_pt int, third_pt int)
  RETURNS SETOF slope_intercept_r2_coefficient AS $$
BEGIN
  RETURN QUERY(
    WITH x AS (
      (SELECT 1 index_col, first_pt value_col UNION SELECT 2, second_pt UNION SELECT 3, third_pt)
      ) SELECT regr_slope(index_col, value_col) slope, regr_intercept(index_col, value_col) intercept, regr_r2(index_col, value_col) r2_coefficient FROM x
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_analytic_window_traffic_difference(checked_detector_id int)
  RETURNS TABLE(
    starttime_ timestamp,
    count_ smallint,
    previous_1_count smallint,
    previous_2_count smallint,
    previous_3_count smallint,
    traffic_diff_ smallint
) AS $$
BEGIN
  RETURN QUERY (
    WITH ordered_series AS (
      SELECT starttime, count FROM traffic WHERE detector_id=checked_detector_id ORDER BY starttime
      ) SELECT
          starttime,
          count,
          LAG(count, 1) OVER (ORDER BY starttime) previous_1_count,
          LAG(count, 2) OVER (ORDER BY starttime) previous_2_count,
          LAG(count, 3) OVER (ORDER BY starttime) previous_3_count,
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


create table how_much_same_differences_cache
(
  detector_id int,
  difference_value int,
  count int
);


CREATE OR REPLACE FUNCTION check_traffic_diff_for_anomaly(checked_detector_id int, interquartile_multiplier real default 1.5) RETURNS VOID AS $$
DECLARE
  it_row record;
  thresholds neg_pos_outlier_thresholds;
  linear_regression_results slope_intercept_r2_coefficient;
  IS_TREND_R2_THRESHOLD real := 0.9;
  FREQUENCY_THRESHOLD int := 100; -- TODO: harcoded frequency threshold -> bit sketchy, this value should correspond to around 0.1% -> 3 standard deviations
  how_much_same_differences int;
  is_record_in_cache_present int;
BEGIN
  thresholds := get_neg_pos_outlier_values_for_traffic_difference(checked_detector_id, interquartile_multiplier);

  FOR it_row IN
    (SELECT * FROM get_analytic_window_traffic_difference(checked_detector_id))
    LOOP
      IF it_row.traffic_diff_ > thresholds.pos_outlier_threshold THEN

        is_record_in_cache_present := (SELECT COUNT(1) FROM how_much_same_differences_cache WHERE
                                    detector_id=checked_detector_id AND difference_value=it_row.traffic_diff_);

        IF is_record_in_cache_present = 0 THEN
          SELECT COUNT(1) INTO how_much_same_differences FROM
                  get_analytic_window_traffic_difference(checked_detector_id) WHERE traffic_diff_=it_row.traffic_diff_;

          INSERT INTO how_much_same_differences_cache(detector_id, difference_value, count)
          VALUES (checked_detector_id, it_row.traffic_diff_, how_much_same_differences);
        END IF;

        SELECT count INTO how_much_same_differences FROM how_much_same_differences_cache
        WHERE detector_id=checked_detector_id AND difference_value=it_row.traffic_diff_;


        if how_much_same_differences < FREQUENCY_THRESHOLD THEN


          SELECT * into linear_regression_results FROM linear_regression_3point(
                                                           it_row.previous_1_count, it_row.previous_2_count, it_row.previous_3_count
                                                         );

          IF linear_regression_results.r2_coefficient < IS_TREND_R2_THRESHOLD THEN
            raise notice 'Noticed POSITIVE OUTLIER anomaly in detector % at: %. Difference between this reading and previous is % || (%, %, %) || %', checked_detector_id, it_row.starttime_, it_row.traffic_diff_, it_row.previous_3_count, it_row.previous_2_count, it_row.previous_1_count, linear_regression_results.r2_coefficient;
          end if;


        end if;



      end IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- max detector id -> 2159
DO $$
  BEGIN
    FOR i in 1 .. 10
      LOOP
        raise notice 'Starting calculation for detector %', i;
        PERFORM check_traffic_diff_for_anomaly(i);
      END LOOP;
  END $$;

-- TODO: maybe dynamic interquartile_multiplier for cases like detector with id 3