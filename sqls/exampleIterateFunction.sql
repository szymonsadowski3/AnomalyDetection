DO $$
  DECLARE
    temprow record;
  BEGIN
    FOR temprow IN
      WITH ordered_series AS ( SELECT starttime, count FROM traffic_extract ORDER BY starttime ) SELECT starttime, count, LAG(count,1) OVER ( ORDER BY starttime ) previous_series_count FROM ordered_series
      LOOP
        raise notice 'Value: %', temprow.count;
      END LOOP;
  END $$;