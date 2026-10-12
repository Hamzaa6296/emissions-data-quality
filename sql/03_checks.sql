-- Automated data validation. Each statement is one check and writes findings
-- into data_quality_issues. Re running the file starts from a clean slate.

TRUNCATE data_quality_issues RESTART IDENTITY;

-- 1. Negative values where the quantity cannot be negative.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'negative_value', 'error', entity_id, year,
       'Negative value found: co2=' || coalesce(co2::text, 'null') ||
       ', methane=' || coalesce(methane::text, 'null') ||
       ', nitrous_oxide=' || coalesce(nitrous_oxide::text, 'null')
FROM emissions
WHERE co2 < 0 OR methane < 0 OR nitrous_oxide < 0 OR population < 0;

-- 2. Countries with a known population but no CO2 figure in the modern era.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'missing_co2', 'warning', em.entity_id, em.year,
       'Population is reported but co2 is missing'
FROM emissions em
JOIN entities en USING (entity_id)
WHERE en.is_country
  AND em.year >= 1990
  AND em.population IS NOT NULL
  AND em.co2 IS NULL;

-- 3. Per capita figure should equal total co2 divided by population.
--    Units: co2 is in million tonnes, so multiply by 1,000,000 first.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'per_capita_mismatch', 'warning', entity_id, year,
       format('co2_per_capita=%s but co2 / population gives %s (difference %s%%)',
              co2_per_capita,
              round(co2 * 1000000 / population, 3),
              round(100 * abs(co2_per_capita - co2 * 1000000 / population)
                    / nullif(co2 * 1000000 / population, 0), 1))
FROM emissions
WHERE co2 > 0 AND population > 0 AND co2_per_capita IS NOT NULL
  -- Values are published with three decimals, so ignore differences that are
  -- only rounding noise (below 0.005 tonnes) and require a 2% relative gap.
  AND abs(co2_per_capita - co2 * 1000000 / population) > 0.005
  AND abs(co2_per_capita - co2 * 1000000 / population)
      > 0.02 * (co2 * 1000000 / population);

-- 4. Large year over year jumps, using LAG over each country's time series.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'yoy_jump', 'warning', entity_id, year,
       format('co2 changed %s%% from %s to %s million tonnes versus the previous year',
              round(100 * (co2 - prev_co2) / prev_co2, 1), prev_co2, co2)
FROM (
    SELECT em.entity_id, em.year, em.co2,
           LAG(em.co2) OVER w AS prev_co2,
           LAG(em.year) OVER w AS prev_year
    FROM emissions em
    JOIN entities en USING (entity_id)
    WHERE en.is_country AND em.co2 IS NOT NULL
    WINDOW w AS (PARTITION BY em.entity_id ORDER BY em.year)
) t
WHERE prev_year = year - 1
  AND prev_co2 >= 5            -- ignore tiny emitters, where percentages are noisy
  AND abs(co2 - prev_co2) / prev_co2 > 0.5;

-- 5. Statistical outliers: year over year change far from the country's own norm.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'yoy_zscore_outlier', 'info', entity_id, year,
       format('Year over year change of %s%% is %s standard deviations from this country''s average',
              round(100 * pct_change, 1), round(z::numeric, 1))
FROM (
    SELECT entity_id, year, pct_change,
           (pct_change - avg(pct_change) OVER (PARTITION BY entity_id))
             / nullif(stddev_samp(pct_change) OVER (PARTITION BY entity_id), 0) AS z
    FROM (
        SELECT em.entity_id, em.year,
               (em.co2 - LAG(em.co2) OVER w) / nullif(LAG(em.co2) OVER w, 0) AS pct_change,
               LAG(em.year) OVER w AS prev_year
        FROM emissions em
        JOIN entities en USING (entity_id)
        WHERE en.is_country AND em.co2 >= 5
        WINDOW w AS (PARTITION BY em.entity_id ORDER BY em.year)
    ) d
    WHERE prev_year = year - 1 AND pct_change IS NOT NULL
) s
WHERE abs(z) > 5;

-- 6. Gaps inside a country's time series (missing years between first and last).
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'year_gap', 'warning', entity_id, prev_year + 1,
       format('No rows for years %s to %s', prev_year + 1, year - 1)
FROM (
    SELECT entity_id, year,
           LAG(year) OVER (PARTITION BY entity_id ORDER BY year) AS prev_year
    FROM emissions
) t
WHERE year - prev_year > 1;

-- 7. Consistency between the World total and the sum of its countries.
--    A small gap is expected (international transport is not assigned to countries),
--    so only large differences are reported.
INSERT INTO data_quality_issues (check_name, severity, entity_id, year, detail)
SELECT 'world_total_mismatch', 'warning', w.entity_id, w.year,
       format('World co2 is %s but countries sum to %s (difference %s%%)',
              round(w.co2, 1), round(c.country_sum, 1),
              round(100 * abs(w.co2 - c.country_sum) / w.co2, 1))
FROM emissions w
JOIN entities we ON we.entity_id = w.entity_id AND we.name = 'World'
JOIN (
    SELECT em.year, sum(em.co2) AS country_sum
    FROM emissions em
    JOIN entities en USING (entity_id)
    WHERE en.is_country AND em.co2 IS NOT NULL
    GROUP BY em.year
) c ON c.year = w.year
WHERE w.year >= 1950
  AND w.co2 > 0
  AND abs(w.co2 - c.country_sum) / w.co2 > 0.10;

-- Summary view used by the API and by the README.
CREATE OR REPLACE VIEW v_quality_summary AS
SELECT check_name, severity, count(*) AS issues,
       min(year) AS first_year, max(year) AS last_year
FROM data_quality_issues
GROUP BY check_name, severity
ORDER BY severity, issues DESC;
