import pg from "pg";
import { createApp } from "./app";

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error("DATABASE_URL is not set. Example: postgres://user:password@localhost:5432/emissions");
  process.exit(1);
}

const pool = new pg.Pool({ connectionString });
const port = Number(process.env.PORT ?? 3000);

createApp(pool).listen(port, () => {
  console.log(`API listening on http://localhost:${port}`);
});
