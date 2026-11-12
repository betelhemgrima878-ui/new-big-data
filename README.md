# Chicago Crime Data ETL Pipeline

## Project Description
This project is an ETL (Extract, Transform, Load) pipeline built to process 2 million records from the City of Chicago Crime Dataset. It uses Python (Pandas) to extract and clean the data, and loads it into a PostgreSQL database using SQLAlchemy (ORM).

## Business Scenario
Analyzing crime patterns to help city officials allocate resources more efficiently.

## Installation
1. Ensure you have Python installed.
2. Install the required dependencies:
   `pip install -r requirements.txt`
3. Ensure PostgreSQL is installed and running on port 5432.

## How to Run
1. Create the database `chicago_crime_db` in PostgreSQL.
2. Run the SQL script in `sql/create_table.sql` to create the table.
3. Open a terminal, navigate to the `src/` folder, and run:
   `python etl_pipeline.py`