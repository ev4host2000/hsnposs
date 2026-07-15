# Shared-hosting diagnostics

Temporary helpers for one-off PostgreSQL checks on shared hosting.

## Rules

- Do **not** commit real credentials.
- Use `db_probe.example.php` as a template.
- Copy locally to `db_probe.php` (gitignored), set `MIZA_DB_*` / `MIZA_DB_PROBE_KEY`, run once, then delete.
- Never deploy `db_probe.php` to a public web root.

## Safe example

```bash
cp db_probe.example.php db_probe.php
export MIZA_DB_PROBE_KEY='...'
export MIZA_DB_HOST=localhost
export MIZA_DB_PORT=5432
export MIZA_DB_NAME='...'
export MIZA_DB_USER='...'
export MIZA_DB_PASSWORD='...'
php db_probe.php
rm db_probe.php
```
