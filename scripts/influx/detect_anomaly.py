import collections

from influxdb import InfluxDBClient

### CFG ###

FREQUENCY_THRESHOLD = 100

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

occurences_aggregation = {}


def nested_set(dict, keys, value):
    for key in keys[:-1]:
        dict = dict.setdefault(key, {})
    dict[keys[-1]] = value


def populate_diff_occurences_for_detector(detector):
    detector_id = detector['detector_id']

    distinct_diffs_query = """
        SELECT DISTINCT(traffic_diff) FROM (
            SELECT difference(count) AS traffic_diff from "sensors".."traffic" WHERE "detector_id" = '{}'
        ) GROUP BY traffic_diff
    """.format(detector['detector_id'])

    distinct_diffs = list(influxClient.query(distinct_diffs_query))[0]

    for distinct_object in distinct_diffs:
        diff_value = distinct_object['distinct']
        count_query = """
            SELECT COUNT(traffic_diff) FROM (SELECT difference(count) AS traffic_diff from "sensors".."traffic") WHERE 
            traffic_diff={}
        """.format(diff_value)

        how_many_occurences = list(influxClient.query(count_query))[0][0]['count']
        # occurences_aggregation[detector][diff_value] = how_many_occurences
        nested_set(occurences_aggregation, [detector_id, diff_value], how_many_occurences)


for detector in detectors[:2]:
    populate_diff_occurences_for_detector(detector)
    result = list(thresholds.get_points(tags=detector))

# SELECT COUNT(traffic_diff) FROM (SELECT difference(count) AS traffic_diff from "sensors".."traffic") WHERE traffic_diff=4.00
# SELECT DISTINCT(traffic_diff) FROM (SELECT difference(count) AS traffic_diff from "sensors".."traffic") GROUP BY traffic_diff
    if len(result) > 0:
        threshold_dict = result[0]
        print(threshold_dict)
        insertQuery = dataQuery.format(threshold_dict['lower_threshold'], threshold_dict['upper_threshold'])
        influxClient.query(insertQuery)
