CREATE TABLE public.flights_2025_01_utc (
    flight_row_id integer PRIMARY KEY,
    flightdate date NOT NULL,
    tail_number text,
    origin text,
    dest text,
    scheduled_departure_utc timestamptz,
    actual_departure_utc timestamptz,
    scheduled_arrival_utc timestamptz,
    actual_arrival_utc timestamptz,
    depdelay numeric,
    arrdelay numeric,
    cancelled numeric,
    diverted numeric,
    arrival_mismatch boolean NOT NULL
);

SELECT
    COUNT(*) AS loaded_rows,
    COUNT(*) FILTER (WHERE arrival_mismatch) AS arrival_mismatches,
    MAX(scheduled_departure_utc AT TIME ZONE 'UTC') FILTER (WHERE flight_row_id = 1879) AS mia_scheduled_utc,
    MAX(actual_departure_utc AT TIME ZONE 'UTC') FILTER (WHERE flight_row_id = 1879) AS mia_actual_utc
FROM public.flights_2025_01_utc;

WITH neighboring_flights AS (
    SELECT
        flight_row_id,
        flightdate,
        tail_number,
        origin,
        dest,
        cancelled,
        actual_departure_utc,
        LAG(dest) OVER by_tail AS previous_dest,
        LAG(
            CASE
                WHEN cancelled = 0 AND diverted = 0 AND NOT arrival_mismatch
                THEN actual_arrival_utc
            END
        ) OVER by_tail AS previous_arrival_utc
    FROM public.flights_2025_01_utc
    WHERE tail_number IS NOT NULL
      AND actual_departure_utc IS NOT NULL
    WINDOW by_tail AS (
        PARTITION BY tail_number
        ORDER BY actual_departure_utc, flight_row_id
    )
)
SELECT
    origin,
    dest,
    previous_dest,
    EXTRACT(EPOCH FROM (actual_departure_utc - previous_arrival_utc)) / 60
        AS ground_minutes
FROM neighboring_flights
WHERE flightdate = DATE '2025-01-15'
  AND tail_number = '196NV'
  AND origin = previous_dest
  AND cancelled = 0
  AND actual_departure_utc >= previous_arrival_utc
ORDER BY actual_departure_utc, flight_row_id;


WITH neighboring_flights AS (
    SELECT
        flightdate,
        origin,
        cancelled,
        depdelay,
        scheduled_departure_utc,
        actual_departure_utc,
        LAG(dest) OVER by_tail AS previous_dest,
        LAG(scheduled_arrival_utc) OVER by_tail AS previous_scheduled_arrival,
        LAG(arrdelay) OVER by_tail AS previous_arrival_delay,
        LAG(
            CASE
                WHEN cancelled = 0 AND diverted = 0 AND NOT arrival_mismatch
                THEN actual_arrival_utc
            END
        ) OVER by_tail AS previous_actual_arrival
    FROM public.flights_2025_01_utc
    WHERE tail_number IS NOT NULL
      AND actual_departure_utc IS NOT NULL
    WINDOW by_tail AS (
        PARTITION BY tail_number
        ORDER BY actual_departure_utc, flight_row_id
    )
),
jan15_turnarounds AS (
    SELECT
        EXTRACT(EPOCH FROM (scheduled_departure_utc - previous_scheduled_arrival)) / 60
            AS scheduled_ground_minutes,
        previous_arrival_delay >= 15 AS previous_arrival_delayed,
        depdelay >= 15 AS departure_delayed
    FROM neighboring_flights
    WHERE flightdate = DATE '2025-01-15'
      AND origin = previous_dest
      AND cancelled = 0
      AND actual_departure_utc >= previous_actual_arrival
      AND previous_arrival_delay IS NOT NULL
)
SELECT
    CASE WHEN scheduled_ground_minutes <= 60 THEN '0–60' ELSE '61–180' END
        AS scheduled_ground_group,
    previous_arrival_delayed,
    COUNT(*) AS pairs,
    COUNT(*) FILTER (WHERE departure_delayed) AS delayed_departures,
    ROUND(100.0 * COUNT(*) FILTER (WHERE departure_delayed) / COUNT(*), 1)
        AS delayed_departure_pct
FROM jan15_turnarounds
WHERE scheduled_ground_minutes > 0
  AND scheduled_ground_minutes <= 180
GROUP BY 1, 2
ORDER BY 1, 2;