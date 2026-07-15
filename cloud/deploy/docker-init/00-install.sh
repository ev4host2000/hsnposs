#!/bin/sh
set -e
cd /schema
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f install_all.sql
