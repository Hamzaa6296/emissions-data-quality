\timing on
-- Query 1: all issues of one type.
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT entity_id, year, detail FROM data_quality_issues WHERE check_name = 'yoy_jump' AND severity = 'warning';

-- Query 2: world total by year, as used by the consistency check.
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT year, sum(co2) FROM emissions WHERE year BETWEEN 2000 AND 2020 GROUP BY year ORDER BY year;
