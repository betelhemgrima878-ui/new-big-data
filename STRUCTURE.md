# Project Structure

```
new big data/
│
├── 📄 README.md                             Main documentation — start here
├── 📄 STRUCTURE.md                          This file
├── 📄 requirements.txt                      Python dependencies (pinned versions)
├── 📄 .env.example                          Credentials template → copy to .env
├── 📄 .gitignore                            Files excluded from Git
│
├── 📁 data/
│   │
│   ├── 📁 raw/                              ⚠ NOT in Git — download separately
│   │   └── 📄 ijzp-q8t2.csv               Source CSV (~1.7 GB, 2M+ rows)
│   │                                        Download:
│   │                                        https://data.cityofchicago.org/api/
│   │                                        views/ijzp-q8t2/rows.csv?accessType=DOWNLOAD
│   │
│   ├── 📁 processed/                        Output of the ETL transform step
│   │   ├── 📄 crime_incidents_sample_10k.csv  First 10,000 cleaned rows (auto-saved by pipeline)
│   │   ├── 📄 null_report.csv               Per-column null counts + fill rules applied
│   │   └── 📄 duplicate_report.csv          Chunk-by-chunk duplicate removal log
│   │
│   ├── 📁 exports/                          Results of BI queries — ready for Excel / Tableau
│   │   ├── 📄 01_yearly_volume.csv          Year-over-year crime totals (2001–2023)
│   │   ├── 📄 02_monthly_trend.csv          Incident counts by month (seasonality)
│   │   ├── 📄 03_top_crime_types.csv        Top 10 crime types with % of total
│   │   ├── 📄 04_arrest_rate_by_type.csv    Arrest rate for 15 crime types
│   │   ├── 📄 05_domestic_split.csv         Domestic vs non-domestic per crime type
│   │   ├── 📄 06_incidents_by_hour.csv      Hourly distribution (0–23)
│   │   ├── 📄 07_incidents_by_day.csv       Day-of-week distribution
│   │   ├── 📄 08_district_summary.csv       Per-district incidents, arrests, % of city
│   │   ├── 📄 09_community_area_summary.csv Top 15 community areas by crime volume
│   │   ├── 📄 10_location_hotspots.csv      Top 15 crime location types
│   │   ├── 📄 11_yoy_change.csv             Year-over-year % change in crime volume
│   │   └── 📄 12_crime_heatmap.csv          Hour × Day of week (168 combinations)
│   │
│   └── 📁 samples/                          ✅ Fully tracked in Git (small files)
│       ├── 📄 sample_raw_100.csv            100 rows of unmodified raw data
│       ├── 📄 sample_cleaned_100.csv        Same 100 rows after ETL transform
│       └── 📄 sample_schema.json            Full data dictionary (all 27 columns)
│
├── 📁 docs/
│   ├── 📄 ETL_Report.md                     Full written project report (10 sections)
│   └── 📄 database_design.md               Schema design, normalisation, index rationale
│
├── 📁 logs/                                 Auto-created at runtime — excluded from Git
│   ├── 📄 etl_pipeline.log                  Timestamped log of every ETL run
│   └── 📄 verification_report.txt           Post-load data quality check results
│
├── 📁 screenshots/
│   ├── 🖼  figure 1.jpg                     ETL pipeline console output
│   ├── 🖼  figure 2.jpg                     PostgreSQL table in pgAdmin
│   └── 🖼  figure3.jpg                      Sample query results
│
├── 📁 sql/
│   ├── 📄 create_table.sql                  Table schema + 15 indexes + column comments
│   └── 📄 analysis_queries.sql              37 BI queries across 8 sections
│
└── 📁 src/
    ├── 📄 config.py                         All settings — reads from .env
    ├── 📄 setup_database.py                 Creates DB + table (run once)
    ├── 📄 etl_pipeline.py                   Main ETL script (Extract → Transform → Load)
    └── 📄 verify_load.py                    Post-load data quality checks
```

---

## Execution Order

```
Step 1 ──► python src/setup_database.py
                │
                ├── Connects to PostgreSQL (localhost:5432)
                ├── Creates database: chicago_crime_db
                └── Runs sql/create_table.sql
                    → Creates crime_incidents table
                    → Creates 15 indexes

Step 2 ──► python src/etl_pipeline.py
                │
                ├── EXTRACT  : Reads data/raw/ijzp-q8t2.csv in 100,000-row chunks
                │
                ├── TRANSFORM (per chunk):
                │    • Normalise column names (lowercase + underscores)
                │    • Parse date/updated_on → TIMESTAMP, strip timezone
                │    • Coerce integers (NaN → 0)
                │    • Coerce booleans ("true"/"false" → Python bool)
                │    • Fill text NaNs → 'Unknown'
                │    • Deduplicate on id column
                │    • Derive day_of_week, month, hour from date
                │
                ├── LOAD: Append chunk to PostgreSQL (retry up to 3× on failure)
                │
                └── Saves data/processed/crime_incidents_sample_10k.csv
                    Writes logs/etl_pipeline.log

Step 3 ──► python src/verify_load.py
                │
                ├── Runs 10 automated data-quality checks
                └── Saves logs/verification_report.txt

Step 4 ──► Open sql/analysis_queries.sql in pgAdmin
                │
                ├── Run any of 37 queries across 8 sections
                └── Export results → data/exports/01_yearly_volume.csv … 12_crime_heatmap.csv
```

---

## File Roles

| File | Purpose | Run directly? |
|------|---------|:------------:|
| `src/config.py` | All settings — reads from `.env` | No |
| `src/setup_database.py` | Create DB + table | Yes — once |
| `src/etl_pipeline.py` | Full ETL pipeline | Yes — main script |
| `src/verify_load.py` | Post-load quality checks | Yes — after ETL |
| `sql/create_table.sql` | Schema definition | Via setup_database.py |
| `sql/analysis_queries.sql` | 37 BI queries | In pgAdmin / psql |
| `data/processed/null_report.csv` | Null audit per column | Reference |
| `data/processed/duplicate_report.csv` | Dedup log per chunk | Reference |
| `data/exports/01–12_*.csv` | Query results for reporting | Reference / Tableau |
| `data/samples/sample_schema.json` | Column data dictionary | Reference |
| `docs/ETL_Report.md` | Written project report | Read / Submit |
| `docs/database_design.md` | DB design document | Read / Submit |
| `logs/etl_pipeline.log` | Full pipeline run log | Reference |
| `logs/verification_report.txt` | QA check results | Reference |
| `requirements.txt` | Python packages | `pip install -r` |
| `.env.example` | Credential template | Copy to `.env` |

---

## Key Design Decisions

| Decision | Reason |
|----------|--------|
| **Chunked reading** (100k rows) | 1.7 GB CSV expands to 4–6 GB in RAM — chunking keeps peak memory under 500 MB |
| **SQLAlchemy + psycopg2** | SQLAlchemy handles connection pooling; psycopg2 is the fastest PostgreSQL adapter for Python |
| **Boolean coercion** in transform | Raw CSV stores `"true"`/`"false"` as strings — must map to Python `bool` before INSERT or PostgreSQL raises a type error |
| **Derived columns** (`day_of_week`, `month`, `hour`) | Pre-computed at load time — avoids `EXTRACT()` on 2M rows at every query, indexes make them instant |
| **15 indexes** | Covers every common filter and GROUP BY column — queries drop from 15–30 sec to under 1 sec |
| **Single wide fact table** | Analytical workload with no JOINs needed — standard data warehouse pattern (denormalised by design) |
| **Retry logic** (3×, exponential back-off) | Prevents a brief DB hiccup from aborting an 8-minute load |
| **Environment variables** | Credentials never hard-coded — `.env` excluded from Git |
| **Separate verify script** | Validation decoupled from loading — re-runnable at any time, produces a saved report |
