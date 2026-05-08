#!/usr/bin/env bash
# api service entrypoint.
#
# Two pre-flight steps before exec'ing node:
#
# 1. Truncate AES-256 keys to 64 hex chars. LazyCat's `stable_secret`
#    is 128-hex-char (64-byte) but briefer's createCipheriv expects
#    32 bytes (= 64 hex). Without this trim the api crashes the first
#    time someone adds a data source with `RangeError: Invalid key
#    length`. Idempotent — safe on already-trimmed values.
#
# 2. Run `prisma migrate deploy` on every boot. The postgres-seed
#    image already bakes the migrations matching its source pin, but
#    when we later bump api with new migrations the existing user's
#    data dir keeps the OLD baseline — so we have to forward-apply
#    here. `migrate deploy` is idempotent and only runs migrations
#    that aren't recorded in `_prisma_migrations`.

set -euo pipefail

for var in DATASOURCES_ENCRYPTION_KEY ENVIRONMENT_VARIABLES_ENCRYPTION_KEY WORKSPACE_SECRETS_ENCRYPTION_KEY; do
  v="${!var-}"
  if [ "${#v}" -gt 64 ]; then
    export "$var"="${v:0:64}"
  fi
done

if [ -n "${POSTGRES_PRISMA_URL:-}" ] || [ -n "${POSTGRES_HOSTNAME:-}" ]; then
  echo "[api-entrypoint] running prisma migrate deploy"
  ( cd /app/packages/database && npx --no-install prisma migrate deploy ) || \
    echo "[api-entrypoint] WARNING: prisma migrate deploy failed — continuing so node can retry against postgres"
fi

exec "$@"
