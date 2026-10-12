-- Fixture based tests for the validation checks.
-- Everything runs inside a transaction that is rolled back at the end, so the
-- real data is never touched. Run from the project root:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f sql/tests/test_checks.sql

BEGIN;

TRUNCATE emissions, entities, data_quality_issues RESTART IDENTITY CASCADE;

INSERT INTO entities (name, iso_code, is_country) VALUES
  ('Aland',    'AAA', true),   -- year over year jump
  ('Bland',    'BBB', true),   -- negative value
  ('Cland',    'CCC', true),   -- missing co2
  ('Dland',    'DDD', true),   -- gap in years
  ('Eland',    'EEE', true),   -- per capita mismatch and one correct row
  ('Zland',    'ZZZ', true),   -- sits in a year where World does not add up
  ('Xland',    'XXX', true),   -- consistent World total year
  ('Yland',    'YYY', true),
  ('World',    'OWID_WRL', false);

-- Aland: steady 100, then 300 (a +200% jump), then back to 100 (a -66% drop).
INSERT INTO emissions (entity_id, year, co2)
SELECT 1, y, CASE WHEN y = 2003 THEN 300 ELSE 100 END FROM generate_series(2000, 2004) y;

-- Bland: one negative co2 value.
INSERT INTO emissions (entity_id, year, co2) VALUES (2, 2001, -5);

-- Cland: population known, co2 missing.
INSERT INTO emissions (entity_id, year, population, co2) VALUES (3, 2005, 1000000, NULL);

-- Dland: rows for 2000 and 2003 only, so 2001 and 2002 are missing.
INSERT INTO emissions (entity_id, year, co2) VALUES (4, 2000, 10), (4, 2003, 10);

-- Eland: 10 million tonnes and 1 million people means 10 tonnes per person.
INSERT INTO emissions (entity_id, year, population, co2, co2_per_capita) VALUES
  (5, 2020, 1000000, 10, 15),   -- wrong: should be flagged
  (5, 2021, 1000000, 10, 10);   -- right: should not be flagged

-- 2010: World claims 1000 but the only country adds up to 10.
INSERT INTO emissions (entity_id, year, co2) VALUES (6, 2010, 10), (9, 2010, 1000);

-- 2011: World equals the sum of its countries.
INSERT INTO emissions (entity_id, year, co2) VALUES (7, 2011, 60), (8, 2011, 40), (9, 2011, 100);

\i sql/03_checks.sql

CREATE OR REPLACE FUNCTION pg_temp.assert_count(p_check text, p_expected int) RETURNS void AS $$
DECLARE actual int;
BEGIN
  SELECT count(*) INTO actual FROM data_quality_issues WHERE check_name = p_check;
  IF actual <> p_expected THEN
    RAISE EXCEPTION 'FAIL %: expected % issues, found %', p_check, p_expected, actual;
  END IF;
  RAISE NOTICE 'PASS %: % issue(s)', p_check, actual;
END $$ LANGUAGE plpgsql;

SELECT pg_temp.assert_count('yoy_jump', 2);
SELECT pg_temp.assert_count('negative_value', 1);
SELECT pg_temp.assert_count('missing_co2', 1);
SELECT pg_temp.assert_count('year_gap', 1);
SELECT pg_temp.assert_count('per_capita_mismatch', 1);
SELECT pg_temp.assert_count('world_total_mismatch', 1);

ROLLBACK;
