import pandas as pd
from sqlalchemy import create_engine
import time

# --- 1. CONFIGURATION ---
DB_USER = 'postgres'
DB_PASSWORD = '1234'  # <--- CHANGE THIS TO YOUR ACTUAL PASSWORD
DB_HOST = 'localhost'
DB_PORT = '5432'
DB_NAME = 'chicago_crime_db'

# The exact name of the file downloading right now
FILE_PATH = '../data/raw/ijzp-q8t2.csv'

# Create database connection
engine = create_engine(f'postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}')
print("🚀 Starting ETL Process...")
start_time = time.time()

try:
    # --- 2. EXTRACT ---
    print("Reading CSV file...")
    chunk_size = 100000
    total_rows = 0

    # Read the CSV in chunks to prevent memory crashes
    for chunk in pd.read_csv(FILE_PATH, chunksize=chunk_size, low_memory=False):
        
        # --- 3. TRANSFORM ---
        # Convert the API date format to standard timestamp
        if 'date' in chunk.columns:
            chunk['date'] = pd.to_datetime(chunk['date']).dt.tz_localize(None)

        if 'updated_on' in chunk.columns:
            chunk['updated_on'] = pd.to_datetime(chunk['updated_on']).dt.tz_localize(None)

        # Fill missing values (NaNs) in integer columns with 0
        int_cols = ['beat', 'district', 'ward', 'community_area', 'year']
        for col in int_cols:
            if col in chunk.columns:
                chunk[col] = chunk[col].fillna(0).astype(int)

        # Fill missing values in text columns with 'Unknown'
        text_cols = ['primary_type', 'description', 'location_description', 'fbi_code']
        for col in text_cols:
            if col in chunk.columns:
                chunk[col] = chunk[col].fillna('Unknown')

        # --- 4. LOAD ---
        # Append the chunk to the database
        chunk.to_sql('crime_incidents', engine, if_exists='append', index=False, method='multi')
        
        total_rows += len(chunk)
        print(f"✅ Loaded {total_rows:,} rows...")

    print(f"🎉 ETL Complete! Total rows loaded: {total_rows:,}")
    print(f"⏱️ Time taken: {round(time.time() - start_time, 2)} seconds")

except FileNotFoundError:
    print(f"❌ ERROR: Could not find '{FILE_PATH}'. Make sure the file is in the same folder as this script.")
except Exception as e:
    print(f"❌ ERROR: {e}")