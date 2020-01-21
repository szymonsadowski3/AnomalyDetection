import collections

from influxdb import InfluxDBClient
import time

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

detectors = [{dict['key']: dict['value']} for dict in list(result.get_points())]

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
        SELECT difference(count) as diff from "sensors".."traffic" where detector_id = {}
    )
    WHERE ({} diff < {} or diff > {}) and detector_id = {}
    """
)

occurences_aggregation = {}


def nested_set(dict, keys, value):
    for key in keys[:-1]:
        dict = dict.setdefault(key, {})
    dict[keys[-1]] = value


def populate_diff_occurrence_for_detector(detector):
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
        nested_set(occurences_aggregation, [detector_id, diff_value], how_many_occurences)


def get_potential_anomaly_values_based_on_occurrence_frequency(detector_id):
    frequences = occurences_aggregation[detector_id]

    return sorted([key for key, value in frequences.items() if value <= FREQUENCY_THRESHOLD])


def get_filter_by_list_of_values(list_of_values):
    return " OR ".join(["diff = {}".format(value) for value in list_of_values])


start_total = time.time()

for detector in detectors:
    print("Detecting anomalies for detector {}...".format(detector['detector_id']))
    start = time.time()

    populate_diff_occurrence_for_detector(detector)
    result = list(thresholds.get_points(tags=detector))

    if len(result) > 0:
        potential_anomaly_values = get_potential_anomaly_values_based_on_occurrence_frequency(detector['detector_id'])
        potential_anomaly_values_filter = (
            "({}) AND".format(get_filter_by_list_of_values(potential_anomaly_values))
            if len(potential_anomaly_values) > 0 else ""
        )

        threshold_dict = result[0]
        print(threshold_dict)
        insertQuery = dataQuery.format(
            detector['detector_id'],
            potential_anomaly_values_filter,
            threshold_dict['lower_threshold'],
            threshold_dict['upper_threshold']
        )
        print(insertQuery)
        influxClient.query(insertQuery)

    end = time.time()
    print("Finished! Detected anomalies for detector {} in time [s] = {} \n".format(detector['detector_id'], end-start))

end_total = time.time()

print("Finished whole process! Total duration time [s] = {}".format(end_total - start_total))
