import express from "express";
import type { Pool } from "pg";

const MAX_LIMIT = 200;

function parseIntParam(value: unknown, fallback: number, min: number, max: number): number {
  if (value === undefined) return fallback;
  const n = Number(value);
  if (!Number.isInteger(n) || n < min || n > max) {
    throw new HttpError(400, `Query parameter must be an integer between ${min} and ${max}`);
  }
  return n;
}

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function createApp(pool: Pool) {
  const app = express();

  app.get("/health", async (_req, res, next) => {
    try {
      await pool.query("SELECT 1");
      res.json({ status: "ok" });
    } catch (err) {
      next(err);
    }
  });

  // How many issues each check found.
  app.get("/api/quality/summary", async (_req, res, next) => {
    try {
      const { rows } = await pool.query("SELECT * FROM v_quality_summary");
      res.json({ checks: rows });
    } catch (err) {
      next(err);
    }
  });

  // Individual findings, filterable by check and severity, with paging.
  app.get("/api/quality/issues", async (req, res, next) => {
    try {
      const limit = parseIntParam(req.query.limit, 50, 1, MAX_LIMIT);
      const offset = parseIntParam(req.query.offset, 0, 0, 1_000_000);
      const severity = typeof req.query.severity === "string" ? req.query.severity : null;
      const check = typeof req.query.check === "string" ? req.query.check : null;
      if (severity && !["error", "warning", "info"].includes(severity)) {
        throw new HttpError(400, "severity must be error, warning or info");
      }
      // Parameterised query: user input is never concatenated into the SQL.
      const { rows } = await pool.query(
        `SELECT i.issue_id, i.check_name, i.severity, e.name AS entity, i.year, i.detail
           FROM data_quality_issues i
           LEFT JOIN entities e USING (entity_id)
          WHERE ($1::text IS NULL OR i.check_name = $1)
            AND ($2::text IS NULL OR i.severity = $2)
          ORDER BY i.issue_id
          LIMIT $3 OFFSET $4`,
        [check, severity, limit, offset],
      );
      res.json({ limit, offset, count: rows.length, issues: rows });
    } catch (err) {
      next(err);
    }
  });

  // One country's emissions time series, looked up by ISO code.
  app.get("/api/countries/:iso/emissions", async (req, res, next) => {
    try {
      const iso = req.params.iso.toUpperCase();
      if (!/^[A-Z]{3}$/.test(iso)) throw new HttpError(400, "iso must be a three letter code");
      const from = parseIntParam(req.query.from, 1750, 1750, 2100);
      const to = parseIntParam(req.query.to, 2100, 1750, 2100);
      const { rows } = await pool.query(
        `SELECT e.name AS country, em.year, em.co2, em.co2_per_capita, em.population
           FROM emissions em
           JOIN entities e USING (entity_id)
          WHERE e.iso_code = $1 AND em.year BETWEEN $2 AND $3
          ORDER BY em.year`,
        [iso, from, to],
      );
      if (rows.length === 0) throw new HttpError(404, `No data for ${iso} in that range`);
      res.json({ iso, rows });
    } catch (err) {
      next(err);
    }
  });

  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    if (err instanceof HttpError) {
      res.status(err.status).json({ error: err.message });
      return;
    }
    console.error(err);
    res.status(500).json({ error: "Internal server error" });
  });

  return app;
}
