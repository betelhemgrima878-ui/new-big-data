"""
config.py
---------
Central configuration for the Chicago Crime ETL Pipeline.

All runtime settings are read from environment variables (loaded from .env)
with safe defaults as fallback so the pipeline runs out-of-the-box for
local development.

How to use
----------
Any script imports only what it needs:

    from config import DATABASE_URL, CHUNK_SIZE, TABLE_NAME

Never hard-code database credentials in any other file.
Copy .env.example to .env and fill in your real values before running.
"""

import os
import sys
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Load .env  (skipped silently if the file does not exist)
# ---------------------------------------------------------------------------
_ENV_FILE = os.path.join(os.path.dirname(__file__), '..', '.env')
load_dotenv(dotenv_path=_ENV_FILE, override=False)


# ---------------------------------------------------------------------------
# Database connection settings
# ---------------------------------------------------------------------------
DB_USER     : str = os.getenv('DB_USER',     'postgres')
DB_PASSWORD : str = os.getenv('DB_PASSWORD', '1234')
DB_HOST     : str = os.getenv('DB_HOST',     'localhost')
DB_PORT     : str = os.getenv('DB_PORT',     '5432')
DB_NAME     : str = os.getenv('DB_NAME',     'chicago_crime_db')

DATABASE_URL: str = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# SQLAlchemy connection pool — tuned for a single-process ETL workload
POOL_SIZE    : int = 2     # permanent connections kept warm
MAX_OVERFLOW : int = 3     # extra connections allowed under peak load
POOL_TIMEOUT : int = 30    # seconds to wait before raising TimeoutError
POOL_RECYCLE : int = 1800  # recycle connections after 30 min (avoid stale TCP)


# ---------------------------------------------------------------------------
# Filesystem paths  (all absolute, derived from this file's location)
# ---------------------------------------------------------------------------
BASE_DIR       : str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DATA_PATH  : str = os.path.join(BASE_DIR, 'data', 'raw',       'ijzp-q8t2.csv')
PROCESSED_DIR  : str = os.path.join(BASE_DIR, 'data', 'processed')
SAMPLES_DIR    : str = os.path.join(BASE_DIR, 'data', 'samples')
SQL_DIR        : str = os.path.join(BASE_DIR, 'sql')
LOG_DIR        : str = os.path.join(BASE_DIR, 'logs')
LOG_FILE       : str = os.path.join(LOG_DIR,  'etl_pipeline.log')
CHECKPOINT_FILE: str = os.path.join(LOG_DIR,  'etl_checkpoint.txt')


# ---------------------------------------------------------------------------
# ETL tuning parameters
# ---------------------------------------------------------------------------

# Rows per CSV read iteration.
# Raise to 200_000 on machines with 16 GB+ RAM for faster throughput.
# Lower to 50_000 on machines with 4 GB RAM to avoid MemoryError.
CHUNK_SIZE : int = 100_000

# Sub-batch size for each individual SQL INSERT statement.
# Larger = fewer round-trips to PostgreSQL but higher per-statement memory.
SQL_BATCH_SIZE : int = 5_000

# How many times to retry a failed INSERT before marking the chunk as failed.
MAX_RETRIES : int = 3

# Initial back-off between retries in seconds.
# Doubles on each attempt: 2s → 4s → 8s (exponential back-off).
RETRY_BACKOFF : int = 2


# ---------------------------------------------------------------------------
# Target PostgreSQL table
# ---------------------------------------------------------------------------
TABLE_NAME : str = 'crime_incidents'


# ---------------------------------------------------------------------------
# Column classification
# Each list tells the transform step which cleaning rule to apply.
# ---------------------------------------------------------------------------

# Integer columns — NaN filled with 0, cast to int32
INT_COLUMNS : list[str] = [
    'beat',
    'district',
    'ward',
    'community_area',
    'year',
]

# Text columns — NaN filled with 'Unknown', whitespace stripped
TEXT_COLUMNS : list[str] = [
    'primary_type',
    'description',
    'location_description',
    'fbi_code',
    'block',
    'iucr',
    'case_number',
]

# Datetime columns — parsed to pd.Timestamp, timezone stripped
DATE_COLUMNS : list[str] = [
    'date',
    'updated_on',
]

# Boolean columns — 'true'/'false' strings mapped to Python bool, NaN → False
# This is the most common source of load errors if not handled explicitly.
BOOL_COLUMNS : list[str] = [
    'arrest',
    'domestic',
]


# ---------------------------------------------------------------------------
# Start-up validation
# Prints warnings to stderr if critical settings look wrong.
# Does NOT exit — allows the pipeline to fail with a more specific error.
# ---------------------------------------------------------------------------
def _validate_config():
    issues = []

    if DB_PASSWORD in ('', 'your_password_here', 'changeme', '1234'):
        issues.append(
            "DB_PASSWORD appears to be a default or placeholder value. "
            "Update it in your .env file before running in production."
        )
    if not os.path.isdir(BASE_DIR):
        issues.append(f"BASE_DIR does not exist: {BASE_DIR}")
    if CHUNK_SIZE < 1000:
        issues.append(f"CHUNK_SIZE={CHUNK_SIZE} is very low — pipeline will be slow.")
    if CHUNK_SIZE > 500_000:
        issues.append(f"CHUNK_SIZE={CHUNK_SIZE} is very high — may cause MemoryError.")

    for issue in issues:
        print(f"[config WARNING] {issue}", file=sys.stderr)


_validate_config()
