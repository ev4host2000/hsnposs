# Miza Cloud — Database

PostgreSQL 15+ DDL for `mizacloud` database.

## Apply order

```bash
createdb -U postgres mizacloud
psql -U postgres -d mizacloud -f 001_initial_schema.sql
psql -U postgres -d mizacloud -f 002_indexes.sql
psql -U postgres -d mizacloud -f 003_constraints.sql
psql -U postgres -d mizacloud -f 004_seed_data.sql
psql -U postgres -d mizacloud -f 005_functions.sql
psql -U postgres -d mizacloud -f 006_triggers.sql
psql -U postgres -d mizacloud -f 007_views.sql
psql -U postgres -d mizacloud -f 008_permissions.sql
psql -U postgres -d mizacloud -f 009_migrations.sql
```

Or one shot:

```bash
psql -U postgres -d mizacloud -f install_all.sql
```

## Teardown (dev only)

```bash
psql -U postgres -d mizacloud -f 010_cleanup.sql
```

## Validate

```powershell
.\validate_sql.ps1
```

## Reference

- Design: `cloud/database/DATABASE_ARCHITECTURE.md`
- API contracts: `cloud/docs/contracts/`
