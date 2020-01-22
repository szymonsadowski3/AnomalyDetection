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
(75 percentyl + 1.5*przedział międzykwartylowy). Tak przyjęte wartości progowe odpowiadają w przybliżeniu 
3 odchyleniom standardowym powyżej średniej w rozkładzie normalnym. 

![Interquartile range](https://miro.medium.com/max/1100/1*VDPJfQLeXS4dtcw4xFxxXw.png "Interquartile range")

2. Filtr trendu

Ponieważ nasze okno analityczne zawiera kilka punktów historycznych, zatem przy analizowaniu anomalii możemy się nimi posłużyć.
Na podstawie tych punktów wyznaczamy trend - regresją liniową i liczymy dopasowanie owej regresji. Jeżeli dopasowanie jest wysokie,
to znaczy że "podejrzana" wartość nie jest anomalią, bo wpasowuje się do trendu.

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

