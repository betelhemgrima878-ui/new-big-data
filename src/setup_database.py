"""
setup_database.py
-----------------
One-shot script to create the PostgreSQL database and table.

This script:
  1. Connects to the default 'postgres' database
  2. Creates the 'chicago_crime_db' database if it does not exist
  3. Connects to the new database
  4. Runs sql/create_table.sql to create the crime_incidents table and indexes

Run once before executing the ETL pipeline:
    python src/setup_database.py
"""

import os
import sys

import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT

sys.path.insert(0, os.path.dirname(__file__))
from config import DB_USER, DB_PASSWORD, DB_HOST, DB_PORT, DB_NAME


BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SQL_FILE = os.path.join(BASE_DIR, 'sql', 'create_table.sql')


def create_database():
    """Connect to the default postgres DB and create chicago_crime_db."""
    print(f"Connecting to PostgreSQL at {DB_HOST}:{DB_PORT} as '{DB_USER}' …")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database='postgres',   # always exists
        )
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cur = conn.cursor()

        # Check if our database already exists
        cur.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (DB_NAME,)
        )
        if cur.fetchone():
            print(f"  Database '{DB_NAME}' already exists — skipping creation.")
        else:
            cur.execute(f'CREATE DATABASE "{DB_NAME}"')
            print(f"  Database '{DB_NAME}' created successfully.")

        cur.close()
        conn.close()

    except psycopg2.OperationalError as exc:
        print(f"\n[ERROR] Cannot connect to PostgreSQL: {exc}")
        print(
            "  Make sure PostgreSQL is running and your credentials in .env are correct."
        )
        sys.exit(1)


def create_table():
    """Connect to chicago_crime_db and run create_table.sql."""
    print(f"Connecting to '{DB_NAME}' …")
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
        )
        conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        cur = conn.cursor()

        with open(SQL_FILE, 'r', encoding='utf-8') as f:
            sql = f.read()

        cur.execute(sql)
        print(f"  Table 'crime_incidents' and indexes created successfully.")

        cur.close()
        conn.close()

    except psycopg2.Error as exc:
        print(f"\n[ERROR] Failed to create table: {exc}")
        sys.exit(1)


def main():
    print("=" * 55)
    print("  Chicago Crime DB — Database Setup")
    print("=" * 55)
    create_database()
    create_table()
    print("=" * 55)
    print("  Setup complete! You can now run the ETL pipeline:")
    print("    python src/etl_pipeline.py")
    print("=" * 55)


if __name__ == '__main__':
    main()
