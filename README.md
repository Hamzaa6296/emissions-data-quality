# Emissions Data Quality

A PostgreSQL project that loads a public greenhouse gas emissions dataset, runs automated data validation checks written in SQL, and exposes the results through a small REST API written in TypeScript.

I built it to practise three things together: relational data modelling, SQL based data quality checks (window functions, statistics, consistency checks), and a database backed web API with tests.

## Data

The Our World in Data CO2 and Greenhouse Gas Emissions dataset (licensed CC BY 4.0), available at https://github.com/owid/co2-data. The download script fetches it. About 50,000 rows covering 254 countries and regions, from 1750 to 2024. The dataset is not stored in this repository.

## What is in the project

| Path | Purpose |
|---|---|
| `sql/01_schema.sql` | Staging table, normalised `entities` and `emissions` tables, constraints, issue log table |
| `sql/02_load.sql` | Loads the CSV and splits countries from aggregate regions such as World |
| `sql/03_checks.sql` | Seven validation checks that write findings to `data_quality_issues`, plus a summary view |
| `sql/04_indexes.sql` | Indexes added after reading query plans |
| `sql/explain_demo.sql` | `EXPLAIN ANALYZE` queries to compare plans before and after indexing |
| `sql/tests/test_checks.sql` | Fixture based tests, run in a transaction that is rolled back |
| `api/` | Express and TypeScript REST API with tests |

## Validation checks

1. **negative_value**: emissions or population below zero.
2. **missing_co2**: countries with a known population but no CO2 figure since 1990.
3. **per_capita_mismatch**: the published per capita figure differs from total CO2 divided by population by more than 2% (ignoring rounding noise).
4. **yoy_jump**: CO2 changes by more than 50% from one year to the next (uses `LAG` over each country's series).
5. **yoy_zscore_outlier**: a year over year change more than five standard deviations from that country's own average.
6. **year_gap**: missing years inside a country's time series.
7. **world_total_mismatch**: the World total differs from the sum of countries by more than 10%.

These checks flag rows for review. They do not prove the data is wrong. For example, large jumps around 1945 and 1946 in Germany or in the late 1950s in China reflect real historical events, and a human would need to decide which flags are genuine errors.

## Results on the full dataset

| Check | Severity | Findings |
|---|---|---|
| per_capita_mismatch | warning | 249 |
| missing_co2 | warning | 118 |
| yoy_jump | warning | 109 |
| yoy_zscore_outlier | info | 37 |
| year_gap | warning | 23 |
| negative_value | error | 0 |
| world_total_mismatch | warning | 0 |

## Performance notes

On this small dataset most queries already run in a few milliseconds. The one clear improvement was a covering index on `emissions (year) INCLUDE (co2)`: a year range aggregate changed from a sequential scan (about 5.1 ms) to an index only scan (about 1.6 ms) on my machine. The index on the issue log changed the plan from a sequential scan to a bitmap index scan but made no measurable time difference at this size. The value of that index would show up on much larger data. Re run `sql/explain_demo.sql` before and after `sql/04_indexes.sql` to see the plans yourself.

## Run it

You need PostgreSQL 14 or newer with the `psql` client, Python 3 (only for a tiny CSV column helper) and Node.js 18 or newer.

```sh
createdb emissions
export DATABASE_URL=postgres://user:password@localhost:5432/emissions

./scripts/run_all.sh        # downloads data, builds the database, runs checks and SQL tests

cd api
npm install
npm test                    # API tests (the database must be loaded)
npm start                   # http://localhost:3000
```

## API

| Endpoint | Description |
|---|---|
| `GET /health` | Database connectivity check |
| `GET /api/quality/summary` | Issue counts per check |
| `GET /api/quality/issues?check=yoy_jump&severity=warning&limit=20&offset=0` | Individual findings, filterable and paged |
| `GET /api/countries/DEU/emissions?from=2000&to=2020` | One country's time series by ISO code |

Queries are parameterised, input is validated, and there is a test for an injection attempt.

## Possible next steps

- Run the checks on a schedule and keep a history of findings.
- Add a simple chart page for one country's series with flagged years highlighted.
- Add a check for the sum of gas specific CO2 columns against the total.

## Licence

Code: MIT. Data: Our World in Data, CC BY 4.0.
