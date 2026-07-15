#!/bin/sh
# Health monitor — exit 1 if API or DB unhealthy (for cron / alerting)
# RAP-P1-06: default to aggregate /v1/health (includes DB check without leaking detail fields).
# Optional: HEALTH_URL=.../v1/health/database still works (public body is connected-only).
# Optional: HEALTH_DETAIL_TOKEN enables operator detail on health endpoints via X-Health-Token.
set -e

BASE_URL="${HEALTH_URL:-http://nginx/v1/health}"
TIMEOUT="${HEALTH_TIMEOUT:-10}"

WGET_HEADERS=""
if [ -n "${HEALTH_DETAIL_TOKEN:-}" ]; then
  WGET_HEADERS="--header=X-Health-Token:${HEALTH_DETAIL_TOKEN}"
fi

HTTP_CODE=$(wget -q -O /dev/null -S --timeout="${TIMEOUT}" ${WGET_HEADERS} "${BASE_URL}" 2>&1 | awk '/HTTP\// {print $2}' | tail -1)

if [ "${HTTP_CODE}" = "200" ]; then
  echo "[health] OK ${BASE_URL}"
  exit 0
fi

echo "[health] FAIL ${BASE_URL} — HTTP ${HTTP_CODE:-unknown}"
exit 1
