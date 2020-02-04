# Instrukcja uruchomienia przykładu InfluxDB

## Instalacja InfluxDB
Najpierw należy pobrać [pliki InfluxDB](https://portal.influxdata.com/downloads/). 
Można skonfigurować **InfluxDB** do działania jako usługa, ale dla demonstracji wystarczy uruchomić jawnie bazę za pomocą polecenia *influxd*.
Przykład był testowany w **wersji 1.7.9**. Domyślnie InfluxDB startuje serwer na **porcie 8086**.

## Instalacja Chronograf
Dodatkowo dla ułatwionej wizualizacji danych można pobrać narzędzie *Chronograf* w wersji **1.7.17**. 
Uruchamia się go za pomocą polecenia *chronograf*, które domyślnie otwiera serwer na **porcie 8888**. 
Jeśli serwer Influx jest aktywny, Chronograf powinien sam połaczyć się z odpowiednim sourcem. Przykładowe zapytania można uruchamiać w sekcji *Explore*, a typ wizualizacji zmienia się w tabie *Visualization* (na samej górze strony).

## Migracja danych
W przykładzie dane do InfluxDB są bezpośrednio migrowane z bazy PostgreSQL za pomocą pythonowego skryptu *migrate.py*, w którym należy zmienić odpowiednio dane połączenia (są ustawione domyślnie: *baza postgres*, *user postgres*, *hasło postgres*).

Ponieważ danych było bardzo dużo, do testowania użyliśmy pełnych danych z ograniczonej liczby sensorów. Na początku skryptu *migrate.py* znajduje się **zmienna NO_SENSORS**, którą można odpowiedno zmodyfikować do zmiany ilości sensorów migrowanych do bazy.

W pliku **requirements.txt** znajdują się wymagane zależności. Skrypt działa pod pythonem 3.

`pip install -r requirements.txt`

Do uruchomienia migracji wystarczy uruchomić skrypt bez argumentów:

`python migrate.py`

## Sprawdzenie danych

Dane migrują się do influxa pod bazę *"sensors"* w measurement *"traffic"*. Aby sprawdzić zawartość, można użyć następującego query:

`select * from "sensors".."traffic" group by detector_id`

Składnia influxa jest bardzo zbliżona do zwykłej składni SQLowej. Przykłady zapytań znajdują się w [dokumentacji Influx](https://docs.influxdata.com/influxdb/v1.7/query_language/data_exploration/). 

## Detekcja anomalii

Aby wykryć anomalie, wystarczy uruchomić skrypt **detect_anomaly.py**. 

`python detect_anomaly.py`

Wynik detekcji anomalii zostanie wrzucony do measurement *"anomalies"*. Aby pobrać wykryte anomalie, można użyć zapytania: 

`select * from "sensors".."anomalies" group by detector_id`
