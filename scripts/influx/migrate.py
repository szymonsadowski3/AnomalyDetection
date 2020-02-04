NO_SENSORS = 100
# change to change the number of sensors migrated to influx

### PostgreSQL DB info ###
from influxdb import InfluxDBClient
import psycopg2
import psycopg2.extras
postgresql_table_name = ""
conn = psycopg2.connect("dbname=postgres user=postgres " +
                        "password=postgres host=localhost")

### InfluxDB info ####
influx_db_name = "sensors"
influxClient = InfluxDBClient("localhost", "8086", database=influx_db_name)
influxClient.drop_database(influx_db_name)
influxClient.create_database(influx_db_name)

# dictates how columns will be mapped to key/fields in InfluxDB
schema = {
    "time_column": "starttime",  # the column that will be used as the time stamp in influx
    "columns_to_fields": ["count"],  # columns that will map to fields
    "columns_to_tags": ["detector_id"],  # columns that will map to tags
    "table_name_to_measurement": "traffic",  # table name that will be mapped to measurement
}

'''
Generates an collection of influxdb points from the given SQL records
'''


def generate_influx_points(records):
    influx_points = []
    for record in records:
        tags = {}
        fields = {}

        for tag_label in schema['columns_to_tags']:
            tags[tag_label] = record[tag_label]
        for field_label in schema['columns_to_fields']:
            fields[field_label] = record[field_label]
            
        influx_points.append({
            "measurement": schema['table_name_to_measurement'],
            "tags": tags,
            "time": record[schema['time_column']],
            "fields": fields
        })
    return influx_points


detector_ids = tuple([i for i in range(1,NO_SENSORS+1)])

# query relational DB for all records
curr = conn.cursor('cursor', cursor_factory=psycopg2.extras.RealDictCursor)
# curr = conn.cursor(dictionary=True)
curr.execute("SELECT * FROM " + schema['table_name_to_measurement'] +
             " WHERE detector_id in {} ORDER BY ".format(detector_ids) + schema['time_column'])
row_count = 0
# process 1000 records at a time
while True:
    print("Processing row {}".format(row_count + 1))
    selected_rows = curr.fetchmany(1000)
    print("Write points")
    influxClient.write_points(generate_influx_points(selected_rows))
    print("Points written")
    row_count += 1000
    if len(selected_rows) < 1000:
        break
conn.close()
