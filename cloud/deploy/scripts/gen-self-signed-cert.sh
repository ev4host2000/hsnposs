#!/bin/sh
# Generate self-signed TLS cert for local staging tests (NOT for production)
set -e

DOMAIN="${1:-api-staging.mizapos.com}"
OUT_DIR="$(dirname "$0")/../ssl/live/${DOMAIN}"
mkdir -p "${OUT_DIR}"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "${OUT_DIR}/privkey.pem" \
  -out "${OUT_DIR}/fullchain.pem" \
  -subj "/CN=${DOMAIN}/O=MizaPos/C=SA"

echo "Self-signed cert written to ${OUT_DIR}"
echo "Android devices will need to trust this cert or use a real Let's Encrypt cert."
