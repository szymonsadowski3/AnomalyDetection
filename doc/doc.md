# 6. Wydajność detekcji anomalii w szeregach czasowych

## Wymagania

PostgreSQL wersja 9.4 lub wyższa

do pobrania ze strony: https://www.enterprisedb.com/downloads/postgres-postgresql-downloads

---

InfluxDB wersja 1.7.9 lub wyższa

Chronograf (opcjonalnie do wizualizacji) wersja 1.7.17 lub wyższa

do pobrania ze strony: https://portal.influxdata.com/downloads/

oraz python3

## Instrukcja uruchomienia

### 1. PostgreSQL

Po zainstalowaniu bazy Postgres z wspomnianego uprzednio linka należy załadować do bazy dane.

Aby zasilić bazę danę danymi źródłowymi należy pobrać archiwum dump, a następnie po rozpakowaniu uruchomić wyekstraktowany skrypt w konsoli postgresa:

```
wget http://awing.kis.agh.edu.pl:8080/dump.sql.bz2
bzip2 -d dump.sql.bz2
psql -f dump.sql
```

UWAGA: rozmiar danych źródłowych jest bardzo duży, skrypt może działać przez kilka godzin zanim się wykona

Aby uruchomić analizę, najpierw należy uruchomić skrypt przygotowujący tabele, funkcje oraz typy:

```
psql -f src/postgres/prepare_types_tables_functions.sql
```

Po tym, jak skrypt skończy się wykonywać, można uruchomić analizę (w pliku run_analysis.sql można zmienić wartość parametru LIMIT, aby uruchomić analizę na docelowej liczbie detektorów, domyślnie jest to LIMIT 100):

```
psql -f src/postgres/run_analysis.sql
```

Po zakończeniu działania analizy, wyniki będą dostępne w następujących tabelach:

```sql
SELECT * FROM detected_anomalies;
SELECT * FROM anomaly_detection_durations;
```

### 2. InfluxDB

#### Instalacja InfluxDB
Najpierw należy pobrać [pliki InfluxDB](https://portal.influxdata.com/downloads/). 
Można skonfigurować **InfluxDB** do działania jako usługa, ale dla demonstracji wystarczy uruchomić jawnie bazę za pomocą polecenia *influxd*.
Przykład był testowany w **wersji 1.7.9**. Domyślnie InfluxDB startuje serwer na **porcie 8086**.

#### Instalacja Chronograf
Dodatkowo dla ułatwionej wizualizacji danych można pobrać narzędzie *Chronograf* w wersji **1.7.17**. 
Uruchamia się go za pomocą polecenia *chronograf*, które domyślnie otwiera serwer na **porcie 8888**. 
Jeśli serwer Influx jest aktywny, Chronograf powinien sam połaczyć się z odpowiednim sourcem. Przykładowe zapytania można uruchamiać w sekcji *Explore*, a typ wizualizacji zmienia się w tabie *Visualization* (na samej górze strony).

#### Migracja danych
W przykładzie dane do InfluxDB są bezpośrednio migrowane z bazy PostgreSQL za pomocą pythonowego skryptu *migrate.py*, w którym należy zmienić odpowiednio dane połączenia (są ustawione domyślnie: *baza postgres*, *user postgres*, *hasło postgres*).

Ponieważ danych było bardzo dużo, do testowania użyliśmy pełnych danych z ograniczonej liczby sensorów. Na początku skryptu *migrate.py* znajduje się **zmienna NO_SENSORS**, którą można odpowiedno zmodyfikować do zmiany ilości sensorów migrowanych do bazy.

W pliku **requirements.txt** znajdują się wymagane zależności. Skrypt działa pod pythonem 3.

`pip3 install -r requirements.txt`

Do uruchomienia migracji wystarczy uruchomić skrypt bez argumentów:

`python3 migrate.py`

#### Sprawdzenie danych

Dane migrują się do influxa pod bazę *"sensors"* w measurement *"traffic"*. Aby sprawdzić zawartość, można użyć następującego query:

`select * from "sensors".."traffic" group by detector_id`

Składnia influxa jest bardzo zbliżona do zwykłej składni SQLowej. Przykłady zapytań znajdują się w [dokumentacji Influx](https://docs.influxdata.com/influxdb/v1.7/query_language/data_exploration/). 

#### Detekcja anomalii

Aby wykryć anomalie, wystarczy uruchomić skrypt **detect_anomaly.py**. 

`python3 detect_anomaly.py`

Wynik detekcji anomalii zostanie wrzucony do measurement *"anomalies"*. Aby pobrać wykryte anomalie, można użyć zapytania: 

`select * from "sensors".."anomalies" group by detector_id`

## Porównywane technologie

### Wybór technologii

#### 1. PostgreSQL

Jako pierwszą technologię wybraliśmy bazę danych PostgreSQL. Uzasadnieniem tego wyboru był fakt, że 
skrypt z danymi wejściowymi był przygotowany właśnie dla Postgresa, a także jest to technologia, z którą 
czujemy się najpewniej jeśli chodzi o technologie bazodanowe. Algorytm wykrywania anomalii zaimplementowany
został napisany jako funkcje PL/pgSQL korzystające z wbudowanych funkcji analitycznych dostępnych w Postgresie.

#### 2. InfluxDB

Drugą wybraną przez nas w porównaniu technologią była baza InfluxDB. Jest ona nastawiona na badanie
szeregów czasowych, zatem wpasowywała się w rozwiązywany przez nas problem. Dodatkowym uzasadnieniem
wyboru tej bazy była jej wysoka pozycja w rankingach baz TSDB (Time series database). Ze względu na ograniczone
możliwości bazy, algorytm wykrywania anomalii został napisany w języku Python, jednakże operacje w Pythonie
służyły tylko głównie tworzeniu dynamicznych zapytań, podczas gdy większość przetwarzania jest robiona po stronie
bazy InfluxDB. 

## Podział pracy

- Szymon Sadowski - opracowanie algorytmu, implementacja algorytmu na PostgreSQL, testowanie rozwiązania na InfluxDB
- Krzysztof Szczyrbak - opracowanie algorytmu, implementacja algorytmu na InfluxDB, testowanie rozwiązania na PostgreSQL
- Daniel Mynarski - implementacja algorytmu na InfluxDB, testowanie rozwiązania na PostgreSQL

## Opis algorytmu

### Okno analityczne

Ponieważ w naszym przykładzie badamy natężenie ruchu, zatem analizujemy nagłe wzrosty/spadki
wartości natężenia ruchu, nie zaś same wartości natężenia. Aby obliczyć wzrost/spadek natężenia ruchu, wystarczy
znać 1 punkt wstecz, jednakże w analizie badamy również trend. Zatem jeżeli wykryjemy potencjalną anomalię, musimy zbadać
trend kilku poprzednich pomiarów, ponieważ jeżeli nowy pomiar wpasowuje się w wyznaczony trend, wówczas możemy
uznać, że nie jest on anomalią. Ostatecznie, ze względów obliczeniowych wybraliśmy okno analityczne 3 punktowe skonstruowane
w następujący sposób:

```sql
WITH ordered_series AS (
      SELECT starttime, count FROM traffic WHERE detector_id=checked_detector_id ORDER BY starttime
      ) SELECT
          starttime,
          count,
          LAG(count, 1) OVER (ORDER BY starttime) previous_1_count,
          LAG(count, 2) OVER (ORDER BY starttime) previous_2_count,
          LAG(count, 3) OVER (ORDER BY starttime) previous_3_count,
          ABS(count - (LAG(count, 1) OVER ( ORDER BY starttime ))) traffic_diff,
          starttime - LAG(starttime) OVER (ORDER BY starttime) time_elapsed_from_previous_measurement
        FROM ordered_series
```

W bazie InfluxDB natomiast, aby możliwe było zbadanie wzrostów i spadków natężenia ruchu użyliśmy funkcji "DIFFERENCE".
Bazując na timestampach oblicza ona kolejne różnice między pomiarami (analogicznie do tego jak wyznaczaliśmy różnice w Postgresie).
Nie znaleźliśmy jednak w bazie InfluxDB możliwości zbadania kontekstu szerszego niż tylko 1 punkt wstecz, zatem
wykonana przez nas analiza w InfluxDB jest nieco bardziej okrojona niż ta w PostgreSQL. 

```
SELECT DISTINCT(traffic_diff) FROM (
    SELECT difference(count) AS traffic_diff from "sensors".."traffic" WHERE detector_id = '{}'
) GROUP BY traffic_diff
```


## Algorytm

Algorytm bazuje na kilku filtrach używających funkcji analitycznych

1. Filtr przedziału międzykwartylowego

Bazując na pomyśle opisanym w artykule https://towardsdatascience.com/anomaly-detection-with-sql-7700c7516d1d 
jednym z naszych filtrów jest filtr przedziału międzykwartylowego. W obrębie danego detektora w naszych danych wejściowych
wartość 25 i 75 percentyla danych. Po odjęciu tych wartości dostajemy przedział międzykwartylowy. Za 
anomalie uważamy wszystkie wartości poniżej (25 percentyl - 1.5*przedział międzykwartylowy) oraz powyżej
(75 percentyl + 1.5*przedział międzykwartylowy). Tak przyjęte wartości progowe odpowiadają w przybliżeniu 
3 odchyleniom standardowym powyżej średniej w rozkładzie normalnym. 

![
artile range](https://i2.wp.com/makemeanalyst.com/wp-content/uploads/2017/05/IQR-1.png?resize=431%2C460 "Interquartile range")

2. Filtr trendu

Ponieważ nasze okno analityczne zawiera kilka punktów historycznych, zatem przy analizowaniu anomalii możemy się nimi posłużyć.
Na podstawie tych punktów wyznaczamy trend - regresją liniową i liczymy dopasowanie owej regresji za pomocą wskaźnika r2. 
Jeżeli dopasowanie jest wysokie (za "wysokie" uznajemy takie, dla którego wartość wskaźnika r2 przekracza 0.9), to znaczy że "podejrzana" wartość nie jest anomalią, bo wpasowuje się do trendu.
W filtrze tym użyliśmy funkcji `regr_slope`, `regr_intercept` oraz `regr_r2`:

```sql
SELECT regr_slope(index_col, value_col) slope, regr_intercept(index_col, value_col) intercept, regr_r2(index_col, value_col) r2_coefficient FROM x
```

3. Odrzucanie "dziur" w pomiarach

W niektórzych przypadkach w pomiarach widoczne są "dziury", tzn. między pomiarami występuje duża przerwa, trwająca
powyżej kilku minut, a nawet w skrajnych przypadkach kilka dni. Takie anomalie oznaczamy jedynie jako "potencjalne", 
w przypadku małych "dziur" mogą to być faktycznie anomalie, jednak w przypadku większych "dziur", nie jesteśmy w stanie tego stwierdzić

![times elapsed](https://raw.githubusercontent.com/szymonsadowski3/AnomalyDetection/master/doc/timesElapsed.PNG)

## Wyniki porównania

W poniższej tabeli przedstawiono wyniki porównania między rozwiązaniami. Dla uproszczenia przeliczeń analiza ograniczyła się do danych natężenia
z pierwszych 100 detektorów

|  | PostgreSQL | InfluxDB |
|----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Łączny czas trwania alogrytmu | 662s ~= 11min | 782s ~= 13min |
| Średni czas trwania algorytmu per detektor | 6.67s | 7.91s |
| Komentarze | Łatwiejsza w użyciu, ze względu   na nasze wcześniejsze doświadczenie z tą bazą.     Posiada wiele wbudowanych funkcji analitycznych, pozwalających m. in. na   konstruowanie okien analitycznych,     dopasowywanie regresji liniowych do punktów, obliczanie dopasowania   ("fit") regresji. | Trudniejsza w użyciu, wymagała   od nas "przestawienia" myślenia na bazę TimeSeries.     Podobnie jak PostgreSQL, InfluxDB udostępnia funkcje analityczne. Nie jest   ich tak wiele jak     w Postgresie, jednakże wystarczyły one do zaimplementowania bazowej wersji   naszego algorytmu. Ze względu na wbudowaną możliwość wizualizacji za pomocą   wykresów, przeglądanie danych jest nieco łatwiejsze. Obliczenia na influxDB okazały się wolniejsze, ale można przypisać ten fakt nieoptymalnej implementacji zapytań względem optymalizowanych funkcji PostgreSQL. |
| Natywna możliwość wizualizacji | Brak | Tak |

## Wnioski

Jak widać w powyższej tabeli, w porównaniu lepiej wypadł PostgreSQL, ponieważ szybciej znajdywał anomalie, mimo nawet, że
w Postgresie zaimplementowaliśmy dodatkowy filtr, który sprawdza trend pomiarów na podstawie 3 poprzednich pomiarów. Może to być wynikiem kilku czynników, m. in:

- Ponieważ w InfluxDB część operacji zaimplementowaliśmy w Pythonie, zarówno sam Python jak i operacje wejścia wyjścia mogą skutkować dłuższym czasem działania
- Ponieważ posiadaliśmy wyższe doświadczenie w PostreSQL, niż w InfluxDB, filtry mogliśmy zaimplementować bardziej optymalnie w PostgreSQL, natomiast nasza implementacja w InfluxDB mogła być nieoptymalna
