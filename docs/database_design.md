# Database Design Document
## Chicago Crime ETL Pipeline — chicago_crime_db

---

## 1. Overview

The database uses a **single wide fact table** design. This is a standard pattern in data warehousing and analytical databases where the workload is read-heavy and all queries access the same entity (crime incidents).

| Property | Value |
|----------|-------|
| Database | PostgreSQL 13+ |
| Database name | `chicago_crime_db` |
| Main table | `crime_incidents` |
| Total columns | 27 |
| Total indexes | 15 |
| Approx. row count | 2,000,000+ |
| Approx. table size on disk | ~2.5 GB (table + indexes) |

---

## 2. Entity-Relationship Overview

Because the design uses a single fact table, there are no foreign key relationships. The diagram below shows all columns grouped by category.

```
┌──────────────────────────────────────────────────────────────┐
│                     crime_incidents                          │
├──────────────────────────────────────────────────────────────┤
│  IDENTITY                                                    │
│  ├── id              BIGINT         PK  (source system ID)   │
│  └── case_number     VARCHAR(20)        (CPD report number)  │
│                                                              │
│  INCIDENT DETAILS                                            │
│  ├── date            TIMESTAMP      NOT NULL                 │
│  ├── block           VARCHAR(255)                            │
│  ├── iucr            VARCHAR(10)        (Illinois UCR code)  │
│  ├── primary_type    VARCHAR(100)   NOT NULL DEFAULT Unknown  │
│  ├── description     VARCHAR(255)   NOT NULL DEFAULT Unknown  │
│  ├── location_description VARCHAR(255) NOT NULL              │
│  ├── arrest          BOOLEAN        NOT NULL DEFAULT FALSE   │
│  ├── domestic        BOOLEAN        NOT NULL DEFAULT FALSE   │
│  └── fbi_code        VARCHAR(10)    NOT NULL DEFAULT Unknown  │
│                                                              │
│  GEOGRAPHY                                                   │
│  ├── beat            SMALLINT       (smallest police unit)   │
│  ├── district        SMALLINT       (police district 1–25)   │
│  ├── ward            SMALLINT       (city council ward 1–50) │
│  ├── community_area  SMALLINT       (community area 1–77)    │
│  ├── x_coordinate    DOUBLE PRECISION  (State Plane ESRI)    │
│  ├── y_coordinate    DOUBLE PRECISION  (State Plane ESRI)    │
│  ├── latitude        DOUBLE PRECISION  (WGS 84)              │
│  ├── longitude       DOUBLE PRECISION  (WGS 84)              │
│  └── location        TEXT               "(lat, lon)" string  │
│                                                              │
│  TEMPORAL (source)                                           │
│  ├── year            SMALLINT       NOT NULL (denormalised)  │
│  └── updated_on      TIMESTAMP          (data portal update) │
│                                                              │
│  DERIVED (added by ETL)                                      │
│  ├── day_of_week     VARCHAR(10)        (Monday…Sunday)      │
│  ├── month           SMALLINT           (1–12)               │
│  └── hour            SMALLINT           (0–23)               │
│                                                              │
│  AUDIT                                                       │
│  └── inserted_at     TIMESTAMP      NOT NULL DEFAULT NOW()   │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. Normalisation Discussion

### Why a single table?

A fully normalised (3NF) design for this dataset would split `crime_incidents` into multiple tables:

```
crime_incidents     (id, case_number, date, block, iucr_id, location_id,
                     district_id, beat_id, ward_id, community_area_id, year,
                     arrest, domestic, updated_on)

dim_iucr            (iucr_id, iucr_code, primary_type, description, fbi_code)
dim_location_type   (location_id, location_description)
dim_geography       (geo_id, district, beat, ward, community_area,
                     x_coordinate, y_coordinate, latitude, longitude)
```

**Why we chose NOT to normalise:**

| Factor | Normalised (3NF) | Single Wide Table |
|--------|-----------------|------------------|
| Query complexity | Requires JOINs on every query | No JOINs — simpler queries |
| Write performance | Faster individual INSERTs | Slightly slower per row |
| Read performance at 2M rows | Slower (JOIN overhead) | Faster (single table scan) |
| Storage efficiency | Smaller (less repetition) | Larger (~15% more) |
| Analyst usability | Harder (need to know schema) | Easier (one table) |
| Assignment workload | Fits OLTP design | Fits OLAP / data warehouse design |

For an **analytical / data warehouse** workload — which this assignment explicitly is — the wide fact table is the correct choice. This is the same pattern used in professional BI tools (star schema fact tables) and analytical databases (BigQuery, Redshift, Snowflake).

### What level of normalisation is applied?

The design is in **1NF** (each column holds a single atomic value, no repeating groups) but intentionally **not** in 3NF. The `year` column is a computed attribute of `date` (a 3NF violation), but it is kept because it dramatically speeds up `GROUP BY year` queries across 2 million rows.

---

## 4. Index Design & Justification

### Full index list

```sql
-- Temporal (5 indexes)
CREATE INDEX idx_crime_date         ON crime_incidents (date);
CREATE INDEX idx_crime_year         ON crime_incidents (year);
CREATE INDEX idx_crime_month        ON crime_incidents (month);
CREATE INDEX idx_crime_hour         ON crime_incidents (hour);
CREATE INDEX idx_crime_day_of_week  ON crime_incidents (day_of_week);

-- Crime type (3 indexes)
CREATE INDEX idx_crime_primary_type ON crime_incidents (primary_type);
CREATE INDEX idx_crime_iucr         ON crime_incidents (iucr);
CREATE INDEX idx_crime_fbi_code     ON crime_incidents (fbi_code);

-- Geographic (4 indexes)
CREATE INDEX idx_crime_district     ON crime_incidents (district);
CREATE INDEX idx_crime_ward         ON crime_incidents (ward);
CREATE INDEX idx_crime_community    ON crime_incidents (community_area);
CREATE INDEX idx_crime_beat         ON crime_incidents (beat);

-- Outcome flags (2 indexes)
CREATE INDEX idx_crime_arrest       ON crime_incidents (arrest);
CREATE INDEX idx_crime_domestic     ON crime_incidents (domestic);

-- Composite (1 index)
CREATE INDEX idx_crime_type_year_arrest
    ON crime_incidents (primary_type, year, arrest);
```

### Why each index exists

| Index | Justification |
|-------|--------------|
| `idx_crime_date` | Range scans: `WHERE date BETWEEN '2020-01-01' AND '2020-12-31'` |
| `idx_crime_year` | Most common GROUP BY column in BI queries |
| `idx_crime_month` | Seasonal analysis — `GROUP BY month` without full table scan |
| `idx_crime_hour` | Hourly pattern analysis — `GROUP BY hour` |
| `idx_crime_day_of_week` | Day-of-week analysis — `GROUP BY day_of_week` |
| `idx_crime_primary_type` | Most common WHERE filter — `WHERE primary_type = 'THEFT'` |
| `idx_crime_iucr` | IUCR code lookups for specific crime sub-types |
| `idx_crime_fbi_code` | FBI category grouping in Section 5 and 8 queries |
| `idx_crime_district` | Per-district GROUP BY — resource allocation queries |
| `idx_crime_ward` | Ward-level political analysis |
| `idx_crime_community` | Community area analysis — 77 areas |
| `idx_crime_beat` | Finest geographic unit — beat-level patrol analysis |
| `idx_crime_arrest` | Boolean filter: `WHERE arrest = TRUE` |
| `idx_crime_domestic` | Domestic violence filter: `WHERE domestic = TRUE` |
| `idx_crime_type_year_arrest` | Composite — covers the most common 3-column BI query pattern |

### Trade-off: indexes vs. load speed

Each index adds approximately **2–4 minutes** to the initial data load because PostgreSQL must maintain the B-tree structure for every row inserted. With 15 indexes and 2 million rows, this adds ~30–60 minutes to the total setup time compared to loading with no indexes.

For a one-time load followed by millions of analytical reads, this trade-off is entirely worthwhile. The indexes reduce typical BI query time from **15–30 seconds** (full table scan) to **under 1 second** (index scan).

---

## 5. Schema: CREATE TABLE Statement

The full DDL is in `sql/create_table.sql`. Key constraints applied:

| Column | Constraint | Reason |
|--------|-----------|--------|
| `id` | `PRIMARY KEY` | Enforces uniqueness; enables fast lookup by ID |
| `case_number` | `NOT NULL` | Every incident must have a CPD case number |
| `date` | `NOT NULL` | A crime record without a date has no analytical value |
| `primary_type` | `NOT NULL DEFAULT 'Unknown'` | Prevents NULL grouping issues in BI queries |
| `description` | `NOT NULL DEFAULT 'Unknown'` | Same reason |
| `location_description` | `NOT NULL DEFAULT 'Unknown'` | Same reason |
| `arrest` | `NOT NULL DEFAULT FALSE` | Boolean — NULL is not meaningful here |
| `domestic` | `NOT NULL DEFAULT FALSE` | Boolean — NULL is not meaningful here |
| `inserted_at` | `NOT NULL DEFAULT NOW()` | Audit trail — set automatically on INSERT |

---

## 6. How to Inspect the Schema in pgAdmin

1. Connect to `chicago_crime_db` in pgAdmin
2. Navigate to: **Schemas → public → Tables → crime_incidents**
3. Right-click → **Properties** to see columns and types
4. Right-click → **Scripts → SELECT Script** to generate a SELECT template

Or run this SQL to list all columns with their types:

```sql
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'crime_incidents'
ORDER BY ordinal_position;
```

To see all indexes:

```sql
SELECT indexname, indexdef
FROM   pg_indexes
WHERE  tablename = 'crime_incidents'
ORDER  BY indexname;
```
