(
  WITH ordered_series AS (
    SELECT starttime FROM traffic WHERE detector_id=1 ORDER BY starttime
    ) SELECT DISTINCT
          starttime - LAG(starttime) OVER (ORDER BY starttime)
      FROM ordered_series ORDER BY 1
)