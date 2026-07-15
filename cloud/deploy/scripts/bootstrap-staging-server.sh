#!/usr/bin/env bash
# Bootstrap Miza Cloud staging on a Linux VPS (Ubuntu/Debian).
# Run from repository root on the server:
#   sudo bash cloud/deploy/scripts/bootstrap-staging-server.sh
#
# Prerequisites:
#   - DNS A record: api-staging.mizapos.com -> this server
#   - Ports 80 and 443 open in firewall
#   - cloud/.env.staging with strong secrets (see scripts/generate_staging_env.ps1)

set -euo pipefail

DOMAIN="${STAGING_DOMAIN:-api-staging.mizapos.com}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CLOUD_DIR="${REPO_ROOT}/cloud"
ENV_FILE="${CLOUD_DIR}/.env.staging"
COMPOSE_FILE="${CLOUD_DIR}/docker-compose.staging.yml"

log() { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ ! -f "${ENV_FILE}" ]]; then
  die "Missing ${ENV_FILE}. Copy from .env.staging.example and set secrets."
fi

if grep -q 'CHANGE_ME' "${ENV_FILE}"; then
  die "Replace CHANGE_ME values in ${ENV_FILE} before deploy."
fi

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
    return
  fi
  log "Installing Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
}

ensure_self_signed_tls() {
  local cert_dir="${CLOUD_DIR}/deploy/ssl/live/${DOMAIN}"
  if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
    log "TLS cert already present in ${cert_dir}"
    return
  fi
  log "Generating temporary self-signed TLS (replaced by Let's Encrypt below)..."
  bash "${CLOUD_DIR}/deploy/scripts/gen-self-signed-cert.sh" "${DOMAIN}"
}

start_stack() {
  log "Building and starting staging stack..."
  cd "${CLOUD_DIR}"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d --build --wait
}

wait_for_health() {
  local url="https://127.0.0.1/v1/health/database"
  local i
  for i in $(seq 1 30); do
    if curl -kfsS "${url}" >/dev/null 2>&1; then
      log "Health OK: ${url}"
      return 0
    fi
    sleep 2
  done
  warn "Health check timed out â€” inspect: docker compose -f ${COMPOSE_FILE} logs api nginx"
  return 1
}

obtain_letsencrypt() {
  if [[ -f "${CLOUD_DIR}/deploy/ssl/live/${DOMAIN}/fullchain.pem" ]]; then
    # Real LE certs include issuer metadata; self-signed CN only â€” try LE anyway if requested
    :
  fi
  if [[ "${SKIP_LETSENCRYPT:-0}" == "1" ]]; then
    warn "SKIP_LETSENCRYPT=1 â€” keeping self-signed cert (Android may reject HTTPS)."
    return
  fi
  log "Requesting Let's Encrypt certificate for ${DOMAIN}..."
  cd "${CLOUD_DIR}"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" run --rm certbot certonly \
    --webroot -w /var/www/certbot \
    -d "${DOMAIN}" \
    --email "${STAGING_ADMIN_EMAIL:-info@mizapos.com}" \
    --agree-tos --no-eff-email --non-interactive || {
      warn "Certbot failed. Ensure DNS points here and port 80 is open."
      warn "Retry later: docker compose -f docker-compose.staging.yml run --rm certbot certonly ..."
      return 1
    }
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec nginx nginx -s reload || true
  log "Let's Encrypt certificate installed."
}

apply_demo_tenant() {
  if [[ "${STAGING_SEED_DEMO:-1}" != "1" ]]; then
    log "STAGING_SEED_DEMO=0 â€” skipping demo tenant seed."
    return
  fi
  local seed="${CLOUD_DIR}/api/src/Modules/Auth/database/dev_seed.sql"
  [[ -f "${seed}" ]] || die "Missing ${seed}"
  log "Applying demo tenant (owner@store.com / MizaTest123!) â€” Beta QA only."
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U "$(grep '^DB_USER=' "${ENV_FILE}" | cut -d= -f2)" \
    -d "$(grep '^DB_NAME=' "${ENV_FILE}" | cut -d= -f2)" < "${seed}"
}

enable_backup() {
  if [[ "${STAGING_ENABLE_BACKUP:-1}" != "1" ]]; then
    return
  fi
  log "Enabling daily backup profile..."
  cd "${CLOUD_DIR}"
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" --profile backup up -d backup
}

print_summary() {
  cat <<EOF

â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Miza Cloud Staging â€” deploy complete
â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  API:     https://${DOMAIN}/v1/health/database
  Demo:    owner@store.com / MizaTest123!  (if seed applied)
  Company: 550e8400-e29b-41d4-a716-446655440000
  Branch:  660e8400-e29b-41d4-a716-446655440001

  Logs:    cd ${CLOUD_DIR} && docker compose -f docker-compose.staging.yml logs -f api
  Stop:    ${REPO_ROOT}/scripts/deploy_cloud_staging.ps1 -Down  (or docker compose down)

  Android: CloudConfig.staging() â†’ https://${DOMAIN}
           Enable cloud sync in Settings â†’ Data

  Docs:    docs/runbooks/RUNBOOK_STAGING_DEPLOY.md
â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
EOF
}

main() {
  [[ -d "${CLOUD_DIR}" ]] || die "cloud/ not found at ${CLOUD_DIR}"
  if [[ "$(id -u)" -ne 0 ]]; then
    warn "Not root â€” Docker may require sudo membership."
  fi
  install_docker
  ensure_self_signed_tls
  start_stack
  wait_for_health || true
  obtain_letsencrypt || true
  apply_demo_tenant
  enable_backup
  print_summary
}

main "$@"
