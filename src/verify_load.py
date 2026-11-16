"""
verify_load.py
--------------
Post-ETL verification script.

Connects to the database and runs a series of checks to confirm the data
was loaded correctly. Prints a summary report to the console and saves it
to logs/verification_report.txt.

Run from the project root:
    python src/verify_load.py
"""

import os
import sys
from datetime import datetime

from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

sys.path.insert(0, os.path.dirname(__file__))
from config import DATABASE_URL, TABLE_NAME, LOG_DIR


# ─────────────────────────────────────────────────────────────────────────────
# helpers
# ─────────────────────────────────────────────────────────────────────────────

def connect():
    try:
        engine = create_engine(DATABASE_URL, pool_pre_ping=True)
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return engine
    except OperationalError as exc:
        print(f"[ERROR] Cannot connect to database: {exc}")
        sys.exit(1)


def q(engine, sql: str):
    """Execute a SQL string and return the first row."""
    with engine.connect() as conn:
        result = conn.execute(text(sql))
        return result.fetchone()


def qa(engine, sql: str):
    """Execute a SQL string and return all rows."""
    with engine.connect() as conn:
        result = conn.execute(text(sql))
        return result.fetchall()


# ─────────────────────────────────────────────────────────────────────────────
# checks
# ─────────────────────────────────────────────────────────────────────────────

def run_checks(engine) -> list[dict]:
    checks = []

    def add(name: str, sql: str, expectation: str, fmt=None):
        try:
            row = q(engine, sql)
            value = row[0] if row else None
            display = fmt(value) if fmt else str(value)
            checks.append({
                "name"       : name,
                "value"      : display,
                "expectation": expectation,
                "status"     : "OK",
            })
        except Exception as exc:
            checks.append({
                "name"       : name,
                "value"      : str(exc),
                "expectation": expectation,
                "status"     : "FAIL",
            })

    # 1. Total row count
    add(
        "Total rows loaded",
        f"SELECT COUNT(*) FROM {TABLE_NAME}",
        ">= 2,000,000",
        lambda v: f"{v:,}",
    )

    # 2. Null IDs
    add(
        "Rows with NULL id",
        f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE id IS NULL",
        "= 0",
        lambda v: f"{v:,}",
    )

    # 3. Duplicate IDs
    add(
        "Duplicate id values",
        f"SELECT COUNT(*) FROM (SELECT id FROM {TABLE_NAME} GROUP BY id HAVING COUNT(*) > 1) t",
        "= 0",
        lambda v: f"{v:,}",
    )

    # 4. Null dates
    add(
        "Rows with NULL date",
        f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE date IS NULL",
        "= 0 (or very low)",
        lambda v: f"{v:,}",
    )

    # 5. Date range sanity
    add(
        "Earliest incident date",
        f"SELECT MIN(date) FROM {TABLE_NAME}",
        ">= 2001-01-01",
    )
    add(
        "Latest incident date",
        f"SELECT MAX(date) FROM {TABLE_NAME}",
        "<= today",
    )

    # 6. Distinct years
    add(
        "Distinct years present",
        f"SELECT COUNT(DISTINCT year) FROM {TABLE_NAME}",
        ">= 20",
        lambda v: f"{v}",
    )

    # 7. Unknown primary_type
    add(
        "Rows with primary_type = 'Unknown'",
        f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE primary_type = 'Unknown'",
        "ideally = 0",
        lambda v: f"{v:,}",
    )

    # 8. Derived columns populated
    add(
        "Rows with NULL day_of_week",
        f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE day_of_week IS NULL",
        "= 0",
        lambda v: f"{v:,}",
    )

    # 9. Arrest flag distribution
    add(
        "Rows where arrest = TRUE",
        f"SELECT COUNT(*) FROM {TABLE_NAME} WHERE arrest = TRUE",
        "> 0",
        lambda v: f"{v:,}",
    )

    # 10. District coverage
    add(
        "Distinct police districts",
        f"SELECT COUNT(DISTINCT district) FROM {TABLE_NAME} WHERE district > 0",
        ">= 20",
        lambda v: str(v),
    )

    return checks


def top_crime_types(engine):
    rows = qa(engine,
        f"""
        SELECT primary_type, COUNT(*) AS cnt
        FROM   {TABLE_NAME}
        GROUP  BY primary_type
        ORDER  BY cnt DESC
        LIMIT  5
        """
    )
    return rows


# ─────────────────────────────────────────────────────────────────────────────
# report
# ─────────────────────────────────────────────────────────────────────────────

def build_report(checks: list[dict], top_types) -> str:
    lines = []
    lines.append("=" * 65)
    lines.append("  POST-ETL VERIFICATION REPORT")
    lines.append(f"  Generated : {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("=" * 65)

    pass_count = sum(1 for c in checks if c["status"] == "OK")
    fail_count = len(checks) - pass_count

    for c in checks:
        icon = "✅" if c["status"] == "OK" else "❌"
        lines.append(
            f"  {icon}  {c['name']:<40}  {c['value']:<18}  (expect {c['expectation']})"
        )

    lines.append("-" * 65)
    lines.append(f"  Passed: {pass_count} / {len(checks)}   Failed: {fail_count}")
    lines.append("")
    lines.append("  Top 5 Crime Types")
    lines.append("  " + "-" * 40)
    for rank, row in enumerate(top_types, 1):
        lines.append(f"  {rank}. {row[0]:<35} {row[1]:>10,}")
    lines.append("=" * 65)

    return "\n".join(lines)


# ─────────────────────────────────────────────────────────────────────────────

def main():
    print("Connecting to database …")
    engine = connect()

    print("Running verification checks …\n")
    checks    = run_checks(engine)
    top_types = top_crime_types(engine)

    report = build_report(checks, top_types)
    print(report)

    # Save report to logs/
    os.makedirs(LOG_DIR, exist_ok=True)
    report_path = os.path.join(LOG_DIR, "verification_report.txt")
    with open(report_path, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"\nReport saved to: {report_path}")

    # Exit with non-zero code if any check failed (useful in CI pipelines)
    failed = [c for c in checks if c["status"] == "FAIL"]
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
