# Wykrywanie Anomalii - Project

## Porównywane technologie

- PostgreSQL (używając funkcji PL/pgSQL)
- InfluxDB (time series database (TSDB))

## Dane wejściowe

Ponieważ w naszym przykładzie badamy natężenie ruchu, zatem analizujemy nagłe wzrosty/spadki
wartości natężenia ruchu, nie zaś same wartości natężenia. W analizie operujemy zatem na oknie analitycznym
przeglądającym wartości natężenia oraz do 3 puntków wstecz.

## Algorytm

Algorytm bazuje na kilku filtrach używających funkcji analitycznych

1. Filtr przedziału międzykwartylowego

Bazując na pomyśle opisanym w artykule https://towardsdatascience.com/anomaly-detection-with-sql-7700c7516d1d 
jednym z naszych filtrów jest filtr przedziału międzykwartylowego. W obrębie danego detektora w naszych danych wejściowych
wartość 25 i 75 percentyla danych. Po odjęciu tych wartości dostajemy przedział międzykwartylowy. Za 
anomalie uważamy wszystkie wartości poniżej (25 percentyl - 1.5*przedział międzykwartylowy) oraz powyżej
(75 percentyl + 1.5*przedział międzykwartylowy)

2. Filtr trendu

Ponieważ nasze okno analityczne zawiera kilka punktów historycznych, zatem przy analizowaniu anomalii możemy się nimi posłużyć.
Na podstawie tych punktów wyznaczamy trend - regresją liniową i liczymy dopasowanie owej regresji. Jeżeli dopasowanie jest wysokie,
to znaczy że "podejrzana" wartość nie jest anomalią, bo wpasowuje się do trendu.

3. Odrzucanie "dziur" w pomiarach

W niektórzych przypadkach w pomiarach widoczne są "dziury", tzn. między pomiarami występuje duża przerwa, trwająca
powyżej kilku minut, a nawet w skrajnych przypadkach kilka dni. Takie anomalie oznaczamy jedynie jako "potencjalne", 
w pyrzypadku małych "dziur" mogą to być faktycznie anomalie, jednak w przypadku większych "dziur", nie jesteśmy w stanie tego stwierdzić

## Wyniki porównania

TODO

