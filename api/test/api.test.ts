import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import pg from "pg";
import { createApp } from "../src/app";

// These tests need the database to be loaded and the checks to have been run.
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
let server: Server;
let base: string;

before(async () => {
  server = createApp(pool).listen(0);
  base = `http://localhost:${(server.address() as AddressInfo).port}`;
});

after(async () => {
  server.close();
  await pool.end();
});

test("health check returns ok", async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: "ok" });
});

test("summary lists the checks", async () => {
  const res = await fetch(`${base}/api/quality/summary`);
  const body = (await res.json()) as { checks: { check_name: string }[] };
  assert.equal(res.status, 200);
  assert.ok(body.checks.some((c) => c.check_name === "yoy_jump"));
});

test("issues can be filtered by check and are limited", async () => {
  const res = await fetch(`${base}/api/quality/issues?check=year_gap&limit=3`);
  const body = (await res.json()) as { issues: { check_name: string }[] };
  assert.equal(res.status, 200);
  assert.ok(body.issues.length <= 3);
  assert.ok(body.issues.every((i) => i.check_name === "year_gap"));
});

test("invalid parameters are rejected with 400", async () => {
  assert.equal((await fetch(`${base}/api/quality/issues?limit=5000`)).status, 400);
  assert.equal((await fetch(`${base}/api/quality/issues?severity=bad`)).status, 400);
  assert.equal((await fetch(`${base}/api/countries/12/emissions`)).status, 400);
});

test("a country time series is returned in year order", async () => {
  const res = await fetch(`${base}/api/countries/DEU/emissions?from=2000&to=2005`);
  const body = (await res.json()) as { rows: { year: number }[] };
  assert.equal(res.status, 200);
  assert.deepEqual(body.rows.map((r) => r.year), [2000, 2001, 2002, 2003, 2004, 2005]);
});

test("unknown country returns 404", async () => {
  assert.equal((await fetch(`${base}/api/countries/XXX/emissions`)).status, 404);
});

test("SQL injection attempt in the check filter returns no rows and no error", async () => {
  const res = await fetch(`${base}/api/quality/issues?check=${encodeURIComponent("x' OR '1'='1")}`);
  const body = (await res.json()) as { issues: unknown[] };
  assert.equal(res.status, 200);
  assert.equal(body.issues.length, 0);
});
