-- Performance work. Run sql/explain_demo.sql before and after this file to compare.

-- Typical API query: one country's time series, newest first.
-- The primary key (entity_id, year) already serves it.

-- Finding issues by check and severity.
CREATE INDEX IF NOT EXISTS idx_issues_check ON data_quality_issues (check_name, severity);
CREATE INDEX IF NOT EXISTS idx_issues_entity ON data_quality_issues (entity_id, year);

-- Year wide aggregates (such as the World total consistency check) scan by year.
CREATE INDEX IF NOT EXISTS idx_emissions_year ON emissions (year) INCLUDE (co2);

-- Partial index: the modern era rows used by the missing data check.
CREATE INDEX IF NOT EXISTS idx_emissions_modern_missing_co2
    ON emissions (entity_id, year)
    WHERE year >= 1990 AND co2 IS NULL;

ANALYZE emissions;
ANALYZE data_quality_issues;
