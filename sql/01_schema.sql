-- Schema for the emissions data quality project.
-- Source data: Our World in Data CO2 and Greenhouse Gas Emissions dataset.

DROP TABLE IF EXISTS data_quality_issues CASCADE;
DROP TABLE IF EXISTS emissions CASCADE;
DROP TABLE IF EXISTS entities CASCADE;
DROP TABLE IF EXISTS staging_owid CASCADE;

-- Raw rows, loaded exactly as they appear in the CSV (only the columns we use).
CREATE TABLE staging_owid (
    country         text,
    year            integer,
    iso_code        text,
    population      numeric,
    gdp             numeric,
    co2             numeric,
    co2_per_capita  numeric,
    methane         numeric,
    nitrous_oxide   numeric,
    total_ghg       numeric
);

-- One row per country or aggregate region (World, Europe, and so on).
CREATE TABLE entities (
    entity_id   serial PRIMARY KEY,
    name        text NOT NULL UNIQUE,
    iso_code    text,
    is_country  boolean NOT NULL
);

-- One row per entity and year.
CREATE TABLE emissions (
    entity_id       integer NOT NULL REFERENCES entities (entity_id),
    year            integer NOT NULL CHECK (year BETWEEN 1750 AND 2100),
    population      numeric,
    gdp             numeric,
    co2             numeric,   -- million tonnes
    co2_per_capita  numeric,   -- tonnes per person
    methane         numeric,   -- million tonnes CO2 equivalent
    nitrous_oxide   numeric,   -- million tonnes CO2 equivalent
    total_ghg       numeric,   -- million tonnes CO2 equivalent
    PRIMARY KEY (entity_id, year)
);

-- Findings written by the validation checks.
CREATE TABLE data_quality_issues (
    issue_id    bigserial PRIMARY KEY,
    check_name  text NOT NULL,
    severity    text NOT NULL CHECK (severity IN ('error', 'warning', 'info')),
    entity_id   integer REFERENCES entities (entity_id),
    year        integer,
    detail      text NOT NULL,
    detected_at timestamptz NOT NULL DEFAULT now()
);
