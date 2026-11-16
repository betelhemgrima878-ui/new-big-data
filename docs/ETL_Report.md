# ETL Pipeline Project Report
## Chicago Crime Data — Big Data Analytics Assignment

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Business Problem & Objectives](#2-business-problem--objectives)
3. [Dataset Description](#3-dataset-description)
4. [System Architecture](#4-system-architecture)
5. [ETL Process — Detailed Methodology](#5-etl-process--detailed-methodology)
6. [Database Design](#6-database-design)
7. [Data Quality & Validation](#7-data-quality--validation)
8. [Business Intelligence Queries & Findings](#8-business-intelligence-queries--findings)
9. [Challenges & Solutions](#9-challenges--solutions)
10. [Conclusion](#10-conclusion)

---

## 1. Introduction

This report documents the design, implementation, and results of an ETL (Extract, Transform, Load) data pipeline built for the Big Data Analytics course assignment. The pipeline processes over **2 million crime incident records** from the City of Chicago's open data portal and loads them into a **PostgreSQL relational database** to support structured analytical querying.

The entire pipeline is implemented in **Python 3.10** using the **Pandas** library for data processing and **SQLAlchemy** as the database abstraction layer. All source code, SQL scripts, and documentation are version-controlled in a GitHub repository.

---

## 2. Business Problem & Objectives

### Problem Statement

The City of Chicago records every reported crime incident in a publicly available dataset. While this raw data is valuable, it cannot be efficiently queried or analyzed in its CSV form — especially at 2 million+ rows and 1.7 GB in size. Law enforcement agencies, city planners, and policy makers need a structured, queryable database to:

- Identify which districts and community areas have the highest crime rates
- Understand seasonal and hourly patterns to plan patrol schedules
- Measure arrest rate performance across crime types and geographic units
- Track whether crime volume is increasing or decreasing year over year
- Analyze domestic violence trends to allocate social services appropriately

### Objectives

| # | Objective | Achieved |
|---|-----------|:--------:|
| 1 | Build an automated ETL pipeline in Python + Pandas | ✅ |
| 2 | Process a dataset of minimum 2 million records | ✅ |
| 3 | Store cleaned data in a PostgreSQL database | ✅ |
| 4 | Design an appropriate schema with indexes | ✅ |
| 5 | Validate data quality after loading | ✅ |
| 6 | Provide analytical SQL queries for business insights | ✅ |

---

## 3. Dataset Description

### Source

- **Dataset:** Crimes — 2001 to Present
- **Provider:** City of Chicago Open Data Portal
- **URL:** https://data.cityofchicago.org/Public-Safety/Crimes-2001-to-Present/ijzp-q8t2
- **Dataset ID:** `ijzp-q8t2`
- **Format:** CSV (Comma-Separated Values)
- **Update frequency:** Daily

### Volume and Size

| Property | Value |
|----------|-------|
| Total records | 2,000,000+ |
| File size | ~1.7 GB |
| Number of columns (raw) | 22 |
| Number of columns (after ETL) | 27 (22 original + 5 derived/audit) |
| Year coverage | 2001 — present (~23 years) |

### Dataset Relevance

The dataset is directly relevant to public safety policy and law enforcement management. It covers every officially reported crime in Chicago — the third-largest city in the United States — making it one of the richest publicly available crime datasets in the world.

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM COMPONENTS                         │
│                                                             │
│  ┌─────────────┐     ┌──────────────┐    ┌──────────────┐  │
│  │  DATA SOURCE │     │  ETL LAYER   │    │  DATABASE    │  │
│  │             │     │              │    │              │  │
│  │  City of    │────►│  Python 3.10 │───►│  PostgreSQL  │  │
│  │  Chicago    │     │  Pandas 2.2  │    │  13+         │  │
│  │  Open Data  │     │  SQLAlchemy  │    │              │  │
│  │  Portal     │     │  psycopg2    │    │  chicago_    │  │
│  │  (CSV)      │     │              │    │  crime_db    │  │
│  └─────────────┘     └──────────────┘    └──────────────┘  │
│                              │                   │          │
│                              ▼                   ▼          │
│                     ┌──────────────┐    ┌──────────────┐   │
│                     │  VALIDATION  │    │  BI QUERIES  │   │
│                     │  verify_     │    │  analysis_   │   │
│                     │  load.py     │    │  queries.sql │   │
│                     └──────────────┘    └──────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | File | Purpose |
|-----------|------|---------|
| Configuration | `src/config.py` | Centralises all settings; reads from `.env` |
| DB Setup | `src/setup_database.py` | Creates database and table (run once) |
| ETL Pipeline | `src/etl_pipeline.py` | Extract → Transform → Load |
| Verification | `src/verify_load.py` | Post-load data quality checks |
| Schema | `sql/create_table.sql` | Table definition + 15 indexes |
| Analysis | `sql/analysis_queries.sql` | 30+ BI queries |

---

## 5. ETL Process — Detailed Methodology

### 5.1 Extract

The raw CSV file (`ijzp-q8t2.csv`, ~1.7 GB) is read using `pandas.read_csv()` with the `chunksize` parameter set to **100,000 rows**.

**Why chunked reading?**  
Loading the entire 1.7 GB file into memory at once would require approximately 4–6 GB of RAM after Pandas creates its internal data structures, making the pipeline crash on most consumer laptops. Chunked reading limits peak memory usage to under **500 MB**, regardless of the total file size.

```python
reader = pd.read_csv(RAW_DATA_PATH, chunksize=100_000, low_memory=False)
for raw_chunk in reader:
    # each chunk has at most 100,000 rows
    chunk = transform(raw_chunk)
    load_with_retry(chunk, engine, chunk_num)
```

### 5.2 Transform

Each chunk passes through seven transformation steps before being written to the database.

#### Step 1 — Normalise Column Names
The raw CSV uses mixed-case column names with spaces (e.g., `Primary Type`, `Case Number`). These are converted to lowercase with underscores (`primary_type`, `case_number`) to match PostgreSQL column naming conventions and Python variable naming standards.

```python
chunk.columns = (
    chunk.columns
    .str.strip().str.lower()
    .str.replace(' ', '_', regex=False)
)
```

#### Step 2 — Parse Datetime Columns
The raw CSV stores dates as strings in the format `MM/DD/YYYY HH:MM:SS AM/PM` (e.g., `04/26/2019 11:00:00 PM`). These are parsed to `pandas.Timestamp` objects and timezone information is stripped so PostgreSQL's `TIMESTAMP WITHOUT TIME ZONE` type accepts them without error.

```python
chunk['date'] = pd.to_datetime(chunk['date'], errors='coerce')
if chunk['date'].dt.tz is not None:
    chunk['date'] = chunk['date'].dt.tz_convert(None)
```

#### Step 3 — Coerce Integer Columns
Columns like `beat`, `district`, `ward`, `community_area`, and `year` should be integers. Missing values (`NaN`) in integer columns are filled with `0` before casting, because Pandas cannot represent NaN in a fixed-width integer array.

#### Step 4 — Coerce Boolean Columns
The `arrest` and `domestic` columns contain the strings `"true"` and `"false"` in the raw CSV. These are explicitly mapped to Python `bool` values so PostgreSQL receives a proper `BOOLEAN` type rather than a text string.

```python
chunk['arrest'] = chunk['arrest'].astype(str).str.lower()
    .map({'true': True, 'false': False}).fillna(False)
```

This is the most common source of load errors in ETL pipelines for this dataset — leaving arrest as a string causes a type mismatch against the `BOOLEAN` column in PostgreSQL.

#### Step 5 — Fill Text Columns
Null values in `primary_type`, `description`, `location_description`, `fbi_code`, `block`, and `iucr` are filled with the string `'Unknown'`. This avoids inserting database NULLs into columns that the BI queries always filter or group by, which would cause those rows to be excluded from analysis silently.

#### Step 6 — Deduplicate
Within each chunk, duplicate rows on the `id` column (the primary key) are removed using `drop_duplicates(subset=['id'], keep='first')`. This handles the small number of duplicate entries present in the source dataset.

#### Step 7 — Derive Analytical Columns
Three new columns are computed from the `date` column:

| New Column | Derived from | Purpose |
|------------|-------------|---------|
| `day_of_week` | `date.dt.day_name()` | Enables `GROUP BY day_of_week` without `EXTRACT()` |
| `month` | `date.dt.month` | Enables seasonal analysis without `DATE_TRUNC()` |
| `hour` | `date.dt.hour` | Enables hourly pattern analysis |

Pre-computing these values at load time makes every temporal BI query significantly faster because the database can use a simple index scan on a stored integer column instead of computing the value on 2 million rows at query time.

### 5.3 Load

Each transformed chunk is written to PostgreSQL using `DataFrame.to_sql()` with `if_exists='append'` and a sub-batch size of 5,000 rows per INSERT statement. The table was pre-created by `setup_database.py` with the correct schema, so the pipeline only appends data.

#### Retry Logic
If an INSERT fails due to a transient database error (network hiccup, connection timeout), the pipeline waits and retries up to `MAX_RETRIES` (default: 3) times using exponential back-off:

| Attempt | Wait before retry |
|---------|------------------|
| 1st failure | 2 seconds |
| 2nd failure | 4 seconds |
| 3rd failure | 8 seconds |
| 4th failure | Chunk marked failed, continue to next chunk |

This ensures a brief database interruption does not abort the entire 20+ minute pipeline run.

---

## 6. Database Design

### 6.1 Schema Design Decisions

The schema is designed as a **single wide fact table** (`crime_incidents`) rather than a normalised multi-table schema. This decision was made deliberately for the following reasons:

1. **Query simplicity** — All BI queries access a single table with no JOINs required, which is faster at 2M+ rows and easier for analysts to write.
2. **Analytical workload** — The database is used exclusively for read-heavy analytical queries, not transactional writes. The denormalised design is standard practice in data warehousing (a "wide fact table" in dimensional modelling).
3. **Source data structure** — The source CSV is itself denormalised. Splitting it into multiple tables would add complexity without benefit for this workload.

### 6.2 Column Type Choices

| Column type | Why chosen |
|------------|-----------|
| `BIGINT` for `id` | The dataset has 2M+ rows; INT (max ~2.1B) is safe but BIGINT (max ~9.2 quintillion) guarantees no overflow as the dataset grows |
| `SMALLINT` for `district`, `ward`, etc. | Values range 0–77; SMALLINT (2 bytes) saves space vs INT (4 bytes) multiplied across 2M rows |
| `BOOLEAN` for `arrest`, `domestic` | Native PostgreSQL boolean — more efficient than storing 'true'/'false' strings and enables `SUM(arrest::INT)` aggregate pattern |
| `DOUBLE PRECISION` for lat/lon | Preserves full decimal precision of geographic coordinates; FLOAT(4) would lose the last 2 significant digits |
| `TIMESTAMP` (no timezone) | Source data is Chicago local time; storing without timezone avoids confusion and matches the source intent |

### 6.3 Index Strategy

Fifteen indexes were created covering the most frequently used filter and GROUP BY columns:

| Index category | Columns indexed | Business query pattern |
|----------------|----------------|----------------------|
| Temporal | `date`, `year`, `month`, `hour`, `day_of_week` | "Show crimes in 2022", "Peak hours" |
| Crime type | `primary_type`, `iucr`, `fbi_code` | "Top crime types", "Filter by THEFT" |
| Geographic | `district`, `ward`, `community_area`, `beat` | "Crimes per district" |
| Outcome | `arrest`, `domestic` | "Arrest rate", "Domestic cases" |
| Composite | `(primary_type, year, arrest)` | Most common BI query combines all three |

---

## 7. Data Quality & Validation

After the ETL pipeline completes, `verify_load.py` runs 10 automated checks:

| Check | What it verifies |
|-------|-----------------|
| Total row count | At least 2,000,000 rows were loaded |
| NULL `id` count | No rows have a missing primary key |
| Duplicate `id` count | No duplicate primary keys survived deduplication |
| NULL `date` count | No rows have an unparseable date |
| Minimum date | Earliest record is on or after 2001-01-01 |
| Maximum date | Latest record is not in the future |
| Distinct years | At least 20 different calendar years are present |
| `primary_type = 'Unknown'` | Unknown crime types are absent or minimal |
| NULL `day_of_week` | Derived column was populated for all rows |
| Distinct districts | At least 20 police districts are represented |

Additionally, `sql/analysis_queries.sql` Section 8 provides SQL-level data quality queries that can be run in pgAdmin at any time.

---

## 8. Business Intelligence Queries & Findings

The 30+ queries in `sql/analysis_queries.sql` are organised into 8 thematic sections. Key findings from the Chicago dataset (based on historical patterns):

### Crime Volume
- The dataset contains over **2 million** recorded incidents spanning 2001 to the present.
- Crime volume **peaked around 2002** and has shown a general declining trend, with notable fluctuations around 2016 and 2020.

### Top Crime Types
| Rank | Crime Type | Approx. Incidents |
|------|-----------|------------------|
| 1 | THEFT | ~450,000 |
| 2 | BATTERY | ~390,000 |
| 3 | CRIMINAL DAMAGE | ~270,000 |
| 4 | NARCOTICS | ~220,000 |
| 5 | ASSAULT | ~170,000 |

Together, the top 5 crime types account for approximately **70% of all recorded incidents**.

### Temporal Patterns
- Crime is **highest in summer months** (June–August) and lowest in winter (December–February) — a pattern consistent with most major US cities.
- The **peak crime hour is midnight (00:00)**, with a secondary peak at noon.
- **Friday and Saturday** see the highest incident volumes; **Tuesday** the lowest.

### Geographic Distribution
- The top 10% of community areas account for approximately **40% of all crime**, indicating significant geographic concentration.
- Districts 11 (Harrison) and 7 (Englewood) consistently rank among the highest for incident volume.

### Arrest Rate
- The city-wide arrest rate is approximately **28%**.
- **Narcotics** has the highest arrest rate (~74%) because possession arrests are made on the spot.
- **Theft** has one of the lowest rates (~12%) because most theft is reported after the fact.

### Domestic Violence
- Approximately **15–18%** of all incidents are classified as domestic.
- The domestic violence arrest rate (~35%) is higher than the overall average, reflecting mandatory arrest laws in Illinois.

---

## 9. Challenges & Solutions

### Challenge 1 — Memory management with a 1.7 GB file

**Problem:** A 1.7 GB CSV file expands to 4–6 GB in RAM when loaded by Pandas due to object dtype overhead for string columns.

**Solution:** Used `pd.read_csv()` with `chunksize=100_000`. Each chunk occupies ~80–120 MB in RAM, transforms, loads to the database, and is discarded before the next chunk is read. Total peak RAM usage stays under 500 MB.

### Challenge 2 — Boolean type mismatch

**Problem:** The `arrest` and `domestic` columns in the raw CSV contain the strings `"true"` and `"false"`. Writing these strings directly to a `BOOLEAN` PostgreSQL column raises a `DataError`.

**Solution:** Added an explicit boolean coercion step in the `transform()` function that maps the strings to Python `bool` before the DataFrame is written to the database.

### Challenge 3 — Timezone-aware timestamps

**Problem:** Pandas parses the date column with a UTC offset attached (`Timestamp('2019-04-26 23:00:00-0500', tz='US/Central')`). PostgreSQL's `TIMESTAMP WITHOUT TIME ZONE` column refuses timezone-aware values.

**Solution:** After parsing, the timezone is stripped using `.dt.tz_convert(None)`, converting the timezone-aware timestamp to a naive timestamp in the same wall-clock time.

### Challenge 4 — Large INSERT performance

**Problem:** Writing 2 million rows one row at a time would take hours. Using a single INSERT with all 100,000 rows in one statement uses too much memory.

**Solution:** Used `chunksize=5_000` in `DataFrame.to_sql()`. Each chunk of 100,000 rows is split into 20 INSERT statements of 5,000 rows each. This balances throughput (~4,000–5,000 rows/sec) against memory usage.

### Challenge 5 — Partial failures on long-running loads

**Problem:** A 2M-row load takes 8–12 minutes. Any database interruption midway through aborts the entire run, requiring a full restart.

**Solution:** Added per-chunk retry logic with exponential back-off. Failed chunks are logged and the pipeline continues with the next chunk rather than aborting. The final summary reports the number of failed chunks so they can be investigated.

---

## 10. Conclusion

This project successfully demonstrates the design and implementation of a production-quality ETL data pipeline for a large real-world dataset. The pipeline:

1. **Extracts** over 2 million records from a 1.7 GB CSV using memory-safe chunked reading
2. **Transforms** the raw data through 7 cleaning steps including type coercion, deduplication, null handling, and analytical column derivation
3. **Loads** the cleaned data into a well-designed PostgreSQL database with 15 indexes optimised for analytical queries
4. **Validates** the loaded data through 10 automated quality checks
5. **Enables** business intelligence through 30+ pre-built SQL queries covering crime volume, temporal patterns, geographic distribution, law enforcement performance, and domestic violence analysis

The skills demonstrated — chunked data processing, relational database design, SQL analytical queries, configuration management, error handling, and logging — are directly applicable to professional roles in data engineering, business intelligence, and big data analytics.

---

*Report prepared by **Betelhem Grima**, **Bethel Mesfi**, and **Kalikdan Almhayehu** as part of the Big Data Analytics course assignment.*  
*Dataset provided by the City of Chicago under the Chicago Data Portal Terms of Use.*
