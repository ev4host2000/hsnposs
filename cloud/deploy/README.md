# Miza Cloud — Deployment Guide

## Local development (Docker)

From repository root:

```powershell
cd cloud
docker compose up -d --build
```

- API: `http://127.0.0.1:8787/v1/health`
- Database: `localhost:5432` (user/pass `mizacloud` / `mizacloud_dev`)
- Dev seed applied automatically (`owner@store.com` / `MizaTest123!`)

Verify:

```powershell
curl http://127.0.0.1:8787/v1/health/database
```

Stop:

```powershell
docker compose down
```

## Staging (`api-staging.mizapos.com`)

> **دليل كامل:** [`docs/runbooks/RUNBOOK_STAGING_DEPLOY.md`](../../docs/runbooks/RUNBOOK_STAGING_DEPLOY.md)

### سريع — VPS Linux (موصى به)

```powershell
# على Windows — إنشاء أسرار
.\scripts\generate_staging_env.ps1
scp cloud\.env.staging user@SERVER:/opt/mizapos/cloud/
```

```bash
# على السيرفر
cd /opt/mizapos
sudo bash cloud/deploy/scripts/bootstrap-staging-server.sh
```

### 1. Prepare environment

```powershell
cd cloud
Copy-Item .env.staging.example .env.staging
# Edit .env.staging — set DB_PASSWORD, JWT_SECRET (64+ random chars)
```

Generate JWT secret (PowerShell):

```powershell
[Convert]::ToBase64String((1..48 | ForEach-Object { Get-Random -Maximum 256 }) -as [byte[]])
```

### 2. TLS certificates

**Production (Let's Encrypt)** — on the staging server:

```bash
docker compose -f docker-compose.staging.yml run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d api-staging.mizapos.com \
  --email info@mizapos.com --agree-tos --no-eff-email
```

Certs land in `deploy/ssl/live/api-staging.mizapos.com/`.

**Local HTTPS test** (self-signed):

```bash
sh deploy/scripts/gen-self-signed-cert.sh api-staging.mizapos.com
```

### 3. Deploy

```powershell
# From repo root
.\scripts\deploy_cloud_staging.ps1
```

Or manually:

```powershell
cd cloud
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d --build
```

### 4. Health monitoring

Cron example (every 5 minutes):

```cron
*/5 * * * * docker compose -f /opt/mizapos/cloud/docker-compose.staging.yml exec -T api sh /var/www/html/../deploy/scripts/healthcheck.sh
```

Or hit externally: `GET https://api-staging.mizapos.com/v1/health/database`

### 5. Backups

Enable daily `pg_dump`:

```powershell
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile backup up -d backup
```

Backups stored in `deploy/backups/`. Test restore:

```bash
gunzip -c deploy/backups/mizacloud_YYYYMMDD_HHMMSS.sql.gz | pg_restore -d mizacloud_test
```

## Android client → staging

Build with staging config (or override base URL in dev settings):

- `CloudConfig.staging()` → `https://api-staging.mizapos.com`
- Enable cloud sync in Settings → Data
- Login with staging tenant credentials (seed manually on staging DB)

## Security checklist (staging)

| Item | Env var |
|------|---------|
| `APP_DEBUG=false` | `.env.staging` |
| Strong `JWT_SECRET` | `.env.staging` |
| Rate limit on login | `RATE_LIMIT_*` (default 10/min) |
| CORS origins | `CORS_ALLOWED_ORIGINS` |
| TLS | nginx + Let's Encrypt |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| 502 Bad Gateway | `docker compose logs api` — check DB connection |
| DB init failed | `docker compose down -v` then `up` (destroys data) |
| CORS blocked | Add app origin to `CORS_ALLOWED_ORIGINS` |
| 429 on login | Wait `RATE_LIMIT_LOGIN_WINDOW` seconds or raise limit in dev |
