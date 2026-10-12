#!/bin/sh
# Builds the database, loads the data, runs the validation checks and the SQL tests.
# Usage: DATABASE_URL=postgres://user:password@localhost:5432/emissions ./scripts/run_all.sh
set -e
: "${DATABASE_URL:?Set DATABASE_URL first}"
[ -f data/owid-co2-data.csv ] || ./scripts/download_data.sh
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f sql/02_load.sql
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f sql/03_checks.sql
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f sql/04_indexes.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "SELECT * FROM v_quality_summary"
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f sql/tests/test_checks.sql
echo "All SQL tests passed."
