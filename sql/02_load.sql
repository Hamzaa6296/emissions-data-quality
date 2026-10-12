-- Run from the project root with psql so the relative path resolves:
--   psql "$DATABASE_URL" -f sql/02_load.sql

TRUNCATE emissions, entities, staging_owid RESTART IDENTITY CASCADE;

\copy staging_owid (country, year, iso_code, population, gdp, co2, co2_per_capita, methane, nitrous_oxide, total_ghg) FROM PROGRAM 'python3 scripts/select_columns.py data/owid-co2-data.csv' WITH (FORMAT csv, HEADER true)

-- Entities. In this dataset, rows with a three letter ISO code that does not
-- start with OWID are real countries. Regions and aggregates have no code or an OWID code.
INSERT INTO entities (name, iso_code, is_country)
SELECT DISTINCT
    country,
    iso_code,
    (iso_code IS NOT NULL AND iso_code NOT LIKE 'OWID%')
FROM staging_owid;

INSERT INTO emissions (entity_id, year, population, gdp, co2, co2_per_capita, methane, nitrous_oxide, total_ghg)
SELECT e.entity_id, s.year, s.population, s.gdp, s.co2, s.co2_per_capita, s.methane, s.nitrous_oxide, s.total_ghg
FROM staging_owid s
JOIN entities e ON e.name = s.country;

ANALYZE entities;
ANALYZE emissions;
