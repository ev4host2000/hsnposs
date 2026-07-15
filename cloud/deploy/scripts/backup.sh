#!/bin/sh
# Daily PostgreSQL backup â€” run via docker compose --profile backup
set -e

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
OUT="/backups/mizacloud_${TIMESTAMP}.sql.gz"

echo "[backup] Starting pg_dump â†’ ${OUT}"
pg_dump -Fc | gzip > "${OUT}"
echo "[backup] Done â€” $(du -h "${OUT}" | cut -f1)"

# Keep last 14 daily backups
ls -1t /backups/mizacloud_*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm -f
