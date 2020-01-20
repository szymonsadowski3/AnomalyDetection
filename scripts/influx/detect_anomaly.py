from influxdb import InfluxDBClient

### InfluxDB info ####
influx_db_name = "sensors"
influxClient = InfluxDBClient("localhost", "8086", database=influx_db_name)

result = influxClient.query(
    """
    SHOW TAG VALUES ON "sensors" WITH KEY = "detector_id" 
    """
)

detectors = [{dict['key'] : dict['value']} for dict in list(result.get_points())]

thresholds = influxClient.query(
        """
        SELECT
        percentile_25 - 1.5*iqr as lower_threshold,
        percentile_75 + 1.5*iqr as upper_threshold
        FROM
        (
            SELECT
                percentile(traffic_diff, 25) as percentile_25,
                percentile(traffic_diff, 75) as percentile_75,
                percentile(traffic_diff, 75) - percentile(traffic_diff, 25) as iqr
            FROM 
            (
                SELECT difference(count) AS traffic_diff from "sensors".."traffic"
            )
        ) group by detector_id 
        """
    )

dataQuery = (
    """
    SELECT * 
    INTO "sensors".."anomalies"
    FROM 
    (
        SELECT difference(count) as diff from "sensors".."traffic"
    )
    WHERE diff < {} or diff > {} group by detector_id
    """
)

for detector in detectors[:100]:
    result = list(thresholds.get_points(tags=detector))
    if len(result) > 0:
        threshold_dict = result[0]
        print(threshold_dict)
        insertQuery = dataQuery.format(threshold_dict['lower_threshold'], threshold_dict['upper_threshold'])
        influxClient.query(insertQuery)
