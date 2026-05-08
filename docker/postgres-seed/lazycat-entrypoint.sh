#!/usr/bin/env bash
# postgres-seed entrypoint.
#
# Lazycat binds the host data dir as root-owned. On first boot it is
# also empty, so we:
#   1. chown to postgres
#   2. seed from /opt/briefer/pg-seed if PG_VERSION is missing — the
#      seed already has briefer DB + role + pgvector ext + every
#      prisma migration baked in at image build time
#   3. exec the upstream postgres entrypoint so PG/Docker shutdown
#      and signal handling stay correct

set -euo pipefail

mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  if [ -d /opt/briefer/pg-seed ] && [ -s /opt/briefer/pg-seed/PG_VERSION ]; then
    echo "[postgres-seed] seeding empty data dir from /opt/briefer/pg-seed"
    find /var/lib/postgresql/data -mindepth 1 -delete
    cp -a /opt/briefer/pg-seed/. /var/lib/postgresql/data/
    chown -R postgres:postgres /var/lib/postgresql/data
  else
    echo "[postgres-seed] no seed snapshot found, falling through to upstream initdb"
  fi
fi

# Hand off to the upstream postgres entrypoint (handles initdb if
# data dir still empty, runs /docker-entrypoint-initdb.d/*, exec's
# postgres).
exec docker-entrypoint.sh "$@"
