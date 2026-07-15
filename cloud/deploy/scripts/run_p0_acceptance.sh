#!/bin/sh
# RAP-P1-05 — P0 acceptance suite (Linux / VPS)
# Usage:
#   ./cloud/deploy/scripts/run_p0_acceptance.sh [core|with-p1|http|all]
# Env:
#   MIZA_ACCEPTANCE_CONTAINER  (default: cloud-api-1)
#   MIZA_ACCEPTANCE_BASE_URL     (default: https://api.mizapos.com)
#   MIZA_OPS_EMAIL / MIZA_OPS_PASSWORD  (required for http/all)
set -eu

MODE="${1:-with-p1}"
CONTAINER="${MIZA_ACCEPTANCE_CONTAINER:-cloud-api-1}"
BASE_URL="${MIZA_ACCEPTANCE_BASE_URL:-https://api.mizapos.com}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"
HTTP_PS1="$REPO_ROOT/cloud/api/src/Modules/Admin/test_revoke_device_access.ps1"

STARTED=$(date +%s)
TOTAL=0
PASS=0
FAIL=0
SKIP=0

run_php() {
  ID="$1"
  NAME="$2"
  REL="$3"
  TOTAL=$((TOTAL + 1))
  echo ""
  echo "=== [$ID] $NAME ==="
  echo "Runner: docker exec $CONTAINER php /var/www/html/$REL"
  if docker exec "$CONTAINER" php "/var/www/html/$REL"; then
    echo "[$ID] PASS"
    PASS=$((PASS + 1))
  else
    echo "[$ID] FAIL" >&2
    FAIL=$((FAIL + 1))
  fi
}

run_http() {
  ID="HTTP-P0-01"
  NAME="Device revoke HTTP acceptance"
  TOTAL=$((TOTAL + 1))
  echo ""
  echo "=== [$ID] $NAME ==="
  echo "BaseUrl=$BASE_URL"

  if [ -z "${MIZA_OPS_EMAIL:-}" ] || [ -z "${MIZA_OPS_PASSWORD:-}" ]; then
    echo "[$ID] FAIL — MIZA_OPS_EMAIL and MIZA_OPS_PASSWORD required (no silent skip)" >&2
    FAIL=$((FAIL + 1))
    return
  fi

  if command -v pwsh >/dev/null 2>&1; then
    if pwsh -NoProfile -File "$HTTP_PS1" \
      -BaseUrl "$BASE_URL" \
      -OpsEmail "$MIZA_OPS_EMAIL" \
      -OpsPassword "$MIZA_OPS_PASSWORD" \
      -RequireOps; then
      echo "[$ID] PASS"
      PASS=$((PASS + 1))
    else
      echo "[$ID] FAIL" >&2
      FAIL=$((FAIL + 1))
    fi
    return
  fi

  if command -v powershell >/dev/null 2>&1; then
    if powershell -NoProfile -File "$HTTP_PS1" \
      -BaseUrl "$BASE_URL" \
      -OpsEmail "$MIZA_OPS_EMAIL" \
      -OpsPassword "$MIZA_OPS_PASSWORD" \
      -RequireOps; then
      echo "[$ID] PASS"
      PASS=$((PASS + 1))
    else
      echo "[$ID] FAIL" >&2
      FAIL=$((FAIL + 1))
    fi
    return
  fi

  echo "[$ID] FAIL — PowerShell not found; run HTTP layer from Windows via scripts/run_p0_acceptance.ps1 -Mode Http" >&2
  FAIL=$((FAIL + 1))
}

echo "========================================"
echo " Miza Cloud — P0 Acceptance Suite (P1-05)"
echo " Mode: $MODE"
echo " Container: $CONTAINER"
echo "========================================"

case "$MODE" in
  core|with-p1|all)
    run_php "P0-01" "Device revoke unit" "src/Modules/Admin/test_revoke_device_access_unit.php"
    run_php "P0-02" "Company suspend/close revoke unit" "src/Modules/Admin/test_company_status_revoke_unit.php"
    run_php "P0-05" "Password reset / forgot revoke unit" "src/Modules/Admin/test_password_reset_revoke_unit.php"
    ;;
  http)
    ;;
  *)
    echo "Unknown mode: $MODE (use core|with-p1|http|all)" >&2
    exit 2
    ;;
esac

case "$MODE" in
  with-p1|all)
    run_php "P1-01" "Rate limit unit" "src/Core/Middleware/test_rate_limit_p1_01_unit.php"
    run_php "P1-03" "Forgot-password harden unit" "src/Modules/Auth/test_forgot_password_harden_unit.php"
    run_php "P1-06" "Health detail unit" "src/Modules/Health/test_health_detail_unit.php"
    ;;
esac

case "$MODE" in
  http|all)
    run_http
    ;;
esac

ENDED=$(date +%s)
ELAPSED=$((ENDED - STARTED))

echo ""
echo "========================================"
echo " SUMMARY"
echo " Tests: $TOTAL | PASS: $PASS | FAIL: $FAIL | SKIP: $SKIP"
echo " Elapsed: ${ELAPSED}s"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
