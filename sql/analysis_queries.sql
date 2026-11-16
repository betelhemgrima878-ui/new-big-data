-- =============================================================================
-- analysis_queries.sql
-- Chicago Crime Data — Business Intelligence Queries
-- =============================================================================
-- Description : 30+ analytical SQL queries that answer real business questions
--               for city officials, law enforcement, and analysts.
-- Database    : chicago_crime_db
-- Table       : crime_incidents
-- Prerequisite: ETL pipeline must have completed successfully
-- =============================================================================


-- =============================================================================
-- SECTION 1 — OVERVIEW & VOLUME
-- =============================================================================

-- 1.1  Total number of recorded incidents in the database
SELECT COUNT(*)                         AS total_incidents
FROM   crime_incidents;


-- 1.2  Year-over-year crime volume with arrest totals
SELECT year,
       COUNT(*)                         AS total_incidents,
       SUM(arrest::INT)                 AS total_arrests,
       ROUND(100.0 * SUM(arrest::INT) / COUNT(*), 2) AS arrest_rate_pct
FROM   crime_incidents
GROUP  BY year
ORDER  BY year;


-- 1.3  Monthly trend — all years combined (seasonality check)
SELECT month,
       TO_CHAR(TO_DATE(month::TEXT, 'MM'), 'Month') AS month_name,
       COUNT(*)                         AS incidents
FROM   crime_incidents
GROUP  BY month
ORDER  BY month;


-- 1.4  Total domestic vs. non-domestic incidents (high-level split)
SELECT domestic,
       COUNT(*)                         AS incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
GROUP  BY domestic;


-- 1.5  Incidents loaded per data-portal update batch (data freshness check)
SELECT DATE_TRUNC('month', updated_on)  AS update_month,
       COUNT(*)                         AS records_updated
FROM   crime_incidents
WHERE  updated_on IS NOT NULL
GROUP  BY update_month
ORDER  BY update_month DESC
LIMIT  12;


-- =============================================================================
-- SECTION 2 — CRIME TYPES
-- =============================================================================

-- 2.1  Top 10 most frequent crime types with share of total
SELECT primary_type,
       COUNT(*)                         AS incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
GROUP  BY primary_type
ORDER  BY incidents DESC
LIMIT  10;


-- 2.2  All crime types with volume and arrest rate — full list
SELECT primary_type,
       COUNT(*)                         AS total_incidents,
       SUM(arrest::INT)                 AS arrests_made,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
GROUP  BY primary_type
ORDER  BY total_incidents DESC;


-- 2.3  Domestic vs. non-domestic split per crime type (top 15 by volume)
SELECT primary_type,
       COUNT(*) FILTER (WHERE domestic = TRUE)  AS domestic_incidents,
       COUNT(*) FILTER (WHERE domestic = FALSE) AS non_domestic_incidents,
       COUNT(*)                                  AS total,
       ROUND(100.0 * COUNT(*) FILTER (WHERE domestic = TRUE) / NULLIF(COUNT(*), 0), 2)
                                                 AS domestic_pct
FROM   crime_incidents
GROUP  BY primary_type
ORDER  BY total DESC
LIMIT  15;


-- 2.4  Crime type trend — how each type has changed over the years
SELECT primary_type,
       year,
       COUNT(*)                         AS incidents
FROM   crime_incidents
WHERE  primary_type IN (
    SELECT primary_type FROM crime_incidents
    GROUP  BY primary_type ORDER BY COUNT(*) DESC LIMIT 5
)
GROUP  BY primary_type, year
ORDER  BY primary_type, year;


-- 2.5  Bottom 10 rarest crime types (useful for data anomaly detection)
SELECT primary_type,
       COUNT(*)                         AS incidents
FROM   crime_incidents
GROUP  BY primary_type
ORDER  BY incidents ASC
LIMIT  10;


-- =============================================================================
-- SECTION 3 — TEMPORAL PATTERNS
-- =============================================================================

-- 3.1  Incidents by hour of day — identifies peak crime hours
SELECT hour,
       COUNT(*)                         AS incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
GROUP  BY hour
ORDER  BY hour;


-- 3.2  Incidents by day of week — Monday to Sunday
SELECT day_of_week,
       COUNT(*)                         AS incidents
FROM   crime_incidents
GROUP  BY day_of_week
ORDER  BY
    CASE day_of_week
        WHEN 'Monday'    THEN 1
        WHEN 'Tuesday'   THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday'  THEN 4
        WHEN 'Friday'    THEN 5
        WHEN 'Saturday'  THEN 6
        WHEN 'Sunday'    THEN 7
    END;


-- 3.3  Peak crime hours for the top 5 crime types
SELECT primary_type,
       hour,
       COUNT(*)                         AS incidents
FROM   crime_incidents
WHERE  primary_type IN (
    SELECT primary_type FROM crime_incidents
    GROUP  BY primary_type ORDER BY COUNT(*) DESC LIMIT 5
)
GROUP  BY primary_type, hour
ORDER  BY primary_type, hour;


-- 3.4  Weekday vs. weekend comparison
SELECT
    CASE WHEN day_of_week IN ('Saturday', 'Sunday') THEN 'Weekend'
         ELSE 'Weekday'
    END                                 AS day_type,
    COUNT(*)                            AS incidents,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
GROUP  BY day_type;


-- 3.5  Monthly crime trend broken down by year (last 5 years)
SELECT year,
       month,
       COUNT(*)                         AS incidents
FROM   crime_incidents
WHERE  year >= (SELECT MAX(year) - 4 FROM crime_incidents)
GROUP  BY year, month
ORDER  BY year, month;


-- =============================================================================
-- SECTION 4 — GEOGRAPHIC DISTRIBUTION
-- =============================================================================

-- 4.1  Incidents per police district with share of city total
SELECT district,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_city
FROM   crime_incidents
WHERE  district > 0
GROUP  BY district
ORDER  BY incidents DESC;


-- 4.2  Top 15 community areas by crime volume with arrest rate
SELECT community_area,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  community_area > 0
GROUP  BY community_area
ORDER  BY incidents DESC
LIMIT  15;


-- 4.3  Top 15 crime location types (hotspot environments)
SELECT location_description,
       COUNT(*)                         AS incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
WHERE  location_description != 'Unknown'
GROUP  BY location_description
ORDER  BY incidents DESC
LIMIT  15;


-- 4.4  Ward-level crime summary with arrest performance
SELECT ward,
       COUNT(*)                         AS total_incidents,
       SUM(arrest::INT)                 AS total_arrests,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  ward > 0
GROUP  BY ward
ORDER  BY total_incidents DESC;


-- 4.5  Most crime-active street blocks (top 20)
SELECT block,
       COUNT(*)                         AS incidents
FROM   crime_incidents
WHERE  block IS NOT NULL AND block != 'Unknown'
GROUP  BY block
ORDER  BY incidents DESC
LIMIT  20;


-- =============================================================================
-- SECTION 5 — LAW ENFORCEMENT PERFORMANCE
-- =============================================================================

-- 5.1  Overall city-wide arrest rate
SELECT ROUND(100.0 * SUM(arrest::INT) / COUNT(*), 2) AS overall_arrest_rate_pct
FROM   crime_incidents;


-- 5.2  Arrest rate trend by year (is it improving or declining?)
SELECT year,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / COUNT(*), 2) AS arrest_rate_pct
FROM   crime_incidents
GROUP  BY year
ORDER  BY year;


-- 5.3  Beat-level arrest performance — top 20 beats by incident volume
SELECT beat,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  beat > 0
GROUP  BY beat
ORDER  BY incidents DESC
LIMIT  20;


-- 5.4  Districts with the LOWEST arrest rates (needs improvement)
SELECT district,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  district > 0
GROUP  BY district
HAVING COUNT(*) > 10000       -- only districts with enough volume to be meaningful
ORDER  BY arrest_rate_pct ASC
LIMIT  10;


-- 5.5  FBI code breakdown — which crime categories have the best arrest rates?
SELECT fbi_code,
       COUNT(*)                         AS incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / NULLIF(COUNT(*), 0), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  fbi_code != 'Unknown'
GROUP  BY fbi_code
ORDER  BY incidents DESC;


-- =============================================================================
-- SECTION 6 — ADVANCED / COMBINED INSIGHTS
-- =============================================================================

-- 6.1  Crime heatmap: hour of day × day of week (pivot-ready)
SELECT day_of_week,
       hour,
       COUNT(*)                         AS incidents
FROM   crime_incidents
GROUP  BY day_of_week, hour
ORDER  BY
    CASE day_of_week
        WHEN 'Monday'    THEN 1 WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3 WHEN 'Thursday' THEN 4
        WHEN 'Friday'    THEN 5 WHEN 'Saturday' THEN 6
        WHEN 'Sunday'    THEN 7
    END, hour;


-- 6.2  Year-over-year change in crime volume using window functions
WITH yearly AS (
    SELECT year, COUNT(*) AS incidents
    FROM   crime_incidents
    GROUP  BY year
)
SELECT year,
       incidents,
       LAG(incidents) OVER (ORDER BY year)  AS prev_year,
       incidents - LAG(incidents) OVER (ORDER BY year) AS yoy_change,
       ROUND(
           100.0 * (incidents - LAG(incidents) OVER (ORDER BY year))
           / NULLIF(LAG(incidents) OVER (ORDER BY year), 0), 2
       )                                    AS yoy_change_pct
FROM   yearly
ORDER  BY year;


-- 6.3  3-year rolling average of crime volume (smooths out anomalies)
WITH yearly AS (
    SELECT year, COUNT(*) AS incidents
    FROM   crime_incidents
    GROUP  BY year
)
SELECT year,
       incidents,
       ROUND(
           AVG(incidents) OVER (ORDER BY year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW),
           0
       )                                    AS rolling_3yr_avg
FROM   yearly
ORDER  BY year;


-- 6.4  Crimes concentrated in top 10% of community areas (inequality measure)
WITH area_counts AS (
    SELECT community_area, COUNT(*) AS incidents
    FROM   crime_incidents WHERE community_area > 0
    GROUP  BY community_area
),
total AS (SELECT SUM(incidents) AS city_total FROM area_counts)
SELECT SUM(a.incidents)         AS incidents_in_top_10pct_areas,
       t.city_total,
       ROUND(100.0 * SUM(a.incidents) / t.city_total, 2) AS concentration_pct
FROM   area_counts a, total t
WHERE  a.community_area IN (
    SELECT community_area FROM area_counts ORDER BY incidents DESC
    LIMIT  GREATEST(1, (SELECT COUNT(*) FROM area_counts) / 10)
);


-- 6.5  Crimes by season
SELECT
    CASE
        WHEN month IN (12, 1, 2) THEN 'Winter'
        WHEN month IN (3,  4, 5) THEN 'Spring'
        WHEN month IN (6,  7, 8) THEN 'Summer'
        ELSE                          'Fall'
    END                             AS season,
    COUNT(*)                        AS incidents,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM   crime_incidents
GROUP  BY season
ORDER  BY incidents DESC;


-- =============================================================================
-- SECTION 7 — DOMESTIC VIOLENCE DEEP-DIVE
-- =============================================================================

-- 7.1  Total domestic incidents and arrest rate
SELECT COUNT(*)                         AS domestic_incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / COUNT(*), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  domestic = TRUE;


-- 7.2  Domestic violence trend by year
SELECT year,
       COUNT(*)                         AS domestic_incidents,
       SUM(arrest::INT)                 AS arrests,
       ROUND(100.0 * SUM(arrest::INT) / COUNT(*), 2) AS arrest_rate_pct
FROM   crime_incidents
WHERE  domestic = TRUE
GROUP  BY year
ORDER  BY year;


-- 7.3  Domestic incidents by crime type
SELECT primary_type,
       COUNT(*)                         AS domestic_incidents,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_domestic
FROM   crime_incidents
WHERE  domestic = TRUE
GROUP  BY primary_type
ORDER  BY domestic_incidents DESC
LIMIT  15;


-- 7.4  Where domestic violence most commonly occurs (location type)
SELECT location_description,
       COUNT(*)                         AS incidents
FROM   crime_incidents
WHERE  domestic = TRUE
  AND  location_description != 'Unknown'
GROUP  BY location_description
ORDER  BY incidents DESC
LIMIT  10;


-- 7.5  Community areas with the highest domestic violence rates
SELECT community_area,
       COUNT(*)                         AS total_incidents,
       COUNT(*) FILTER (WHERE domestic = TRUE) AS domestic_incidents,
       ROUND(
           100.0 * COUNT(*) FILTER (WHERE domestic = TRUE) / NULLIF(COUNT(*), 0), 2
       )                                AS domestic_rate_pct
FROM   crime_incidents
WHERE  community_area > 0
GROUP  BY community_area
HAVING COUNT(*) > 1000
ORDER  BY domestic_rate_pct DESC
LIMIT  15;


-- 7.6  Hour of day breakdown for domestic incidents
SELECT hour,
       COUNT(*)                         AS domestic_incidents
FROM   crime_incidents
WHERE  domestic = TRUE
GROUP  BY hour
ORDER  BY hour;


-- =============================================================================
-- SECTION 8 — DATA QUALITY & PIPELINE VALIDATION
-- =============================================================================

-- 8.1  Total row count — confirm 2M+ records loaded
SELECT COUNT(*)                         AS total_rows
FROM   crime_incidents;


-- 8.2  Null value count per key column
SELECT
    COUNT(*) FILTER (WHERE id            IS NULL) AS null_id,
    COUNT(*) FILTER (WHERE case_number   IS NULL) AS null_case_number,
    COUNT(*) FILTER (WHERE date          IS NULL) AS null_date,
    COUNT(*) FILTER (WHERE primary_type  IS NULL OR primary_type = 'Unknown') AS null_primary_type,
    COUNT(*) FILTER (WHERE district      = 0)     AS zero_district,
    COUNT(*) FILTER (WHERE community_area = 0)    AS zero_community_area,
    COUNT(*) FILTER (WHERE latitude      IS NULL) AS null_latitude,
    COUNT(*) FILTER (WHERE longitude     IS NULL) AS null_longitude,
    COUNT(*) FILTER (WHERE day_of_week   IS NULL) AS null_day_of_week,
    COUNT(*) FILTER (WHERE month         IS NULL) AS null_month,
    COUNT(*) FILTER (WHERE hour          IS NULL) AS null_hour
FROM   crime_incidents;


-- 8.3  Duplicate id check — should return 0 rows
SELECT id, COUNT(*)                     AS occurrences
FROM   crime_incidents
GROUP  BY id
HAVING COUNT(*) > 1
LIMIT  10;


-- 8.4  Date range sanity — min/max dates should be 2001 to present
SELECT MIN(date) AS earliest_incident,
       MAX(date) AS latest_incident,
       COUNT(DISTINCT year) AS distinct_years
FROM   crime_incidents;


-- 8.5  Distribution of derived columns — all 24 hours and 7 days present?
SELECT COUNT(DISTINCT hour)        AS distinct_hours,
       COUNT(DISTINCT day_of_week) AS distinct_days,
       COUNT(DISTINCT month)       AS distinct_months
FROM   crime_incidents;


-- 8.6  Top 10 unknown / blank values by column (find data gaps)
SELECT 'primary_type'       AS column_name, COUNT(*) AS blank_count
FROM   crime_incidents WHERE primary_type = 'Unknown'
UNION ALL
SELECT 'location_description',               COUNT(*)
FROM   crime_incidents WHERE location_description = 'Unknown'
UNION ALL
SELECT 'fbi_code',                           COUNT(*)
FROM   crime_incidents WHERE fbi_code = 'Unknown'
UNION ALL
SELECT 'block',                              COUNT(*)
FROM   crime_incidents WHERE block IS NULL OR block = 'Unknown'
ORDER  BY blank_count DESC;


-- 8.7  inserted_at range — confirms all rows were loaded in the same run
SELECT MIN(inserted_at)             AS load_start,
       MAX(inserted_at)             AS load_end,
       MAX(inserted_at) - MIN(inserted_at) AS total_load_duration
FROM   crime_incidents;
