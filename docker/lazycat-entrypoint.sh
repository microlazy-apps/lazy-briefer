#!/bin/bash
# Lazycat entrypoint shim for briefer.
#
# Three things to handle before exec'ing supervisord:
#
# 1. Lazycat binds host paths in as root-owned, but supervisord
#    launches each program under a non-root user. Re-own each bind
#    to its expected owner. We chown only the top-level on already
#    populated dirs to avoid expensive `chown -R` on a 5GB postgres
#    cluster every reboot.
# 2. The upstream image initdb's /var/lib/postgresql/data at build
#    time, but bind-mounting an empty host dir on top hides that
#    cluster. Detect the empty data dir via the PG_VERSION sentinel
#    and seed it from the prebuilt /opt/briefer/pg-seed snapshot the
#    Dockerfile created (which already has the briefer DB + role +
#    pgvector extension + every prisma migration applied — saves the
#    user 30-60s of first-boot wait).
# 3. Same for /home/jupyteruser — the upstream image puts a python
#    venv under there; bind-mounting an empty host dir hides it. Seed
#    from /opt/briefer/jupyter-home-seed on first boot.

set -euo pipefail

# --- normalize encryption key lengths ---
# Briefer uses AES-256-* via Node's createCipheriv, which requires a
# 32-byte key (= 64 hex chars per upstream's setup.py default). LazyCat
# `stable_secret` produces 128-hex-char (64-byte) values, so the api
# crashes with `RangeError: Invalid key length` when adding a data
# source. Truncate to 64 chars before exec'ing supervisord.
for var in DATASOURCES_ENCRYPTION_KEY ENVIRONMENT_VARIABLES_ENCRYPTION_KEY WORKSPACE_SECRETS_ENCRYPTION_KEY; do
  v="${!var-}"
  if [ "${#v}" -gt 64 ]; then
    export "$var"="${v:0:64}"
  fi
done

# --- force IPv4 for `localhost` ---
# Briefer's api process talks to jupyter via http://localhost:8888.
# Node 18+ resolves `localhost` to ::1 first, but jupyter only binds
# IPv4 0.0.0.0 → ECONNREFUSED ::1:8888 on every CSV upload / file
# listing. Strip `localhost` from the IPv6 line so DNS returns only
# 127.0.0.1.
#
# Note: docker mounts /etc/hosts as a bind, so `sed -i` (which uses
# rename(2)) fails with EXDEV. Read into a shell variable, then
# truncate-and-write the file in place.
HOSTS_NEW=$(sed -E '/^::1[[:space:]]/{s/[[:space:]]+localhost([[:space:]]|$)/\1/g}' /etc/hosts)
printf '%s\n' "$HOSTS_NEW" > /etc/hosts

# --- bind ownership fixups (top-level only, fast) ---
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

mkdir -p /home/jupyteruser
chown jupyteruser:jupyteruser /home/jupyteruser

mkdir -p /home/briefer/.config/briefer
chown -R briefer:briefer /home/briefer/.config

# --- postgres data dir bootstrap ---
# Use a pre-seeded snapshot if available (created at image build with
# initdb + prisma migrate already done). Falls back to fresh initdb
# for older images.
if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  if [ -d /opt/briefer/pg-seed ] && [ -s /opt/briefer/pg-seed/PG_VERSION ]; then
    echo "[lazycat-entrypoint] seeding /var/lib/postgresql/data from prebuilt snapshot"
    find /var/lib/postgresql/data -mindepth 1 -delete
    cp -a /opt/briefer/pg-seed/. /var/lib/postgresql/data/
    chown -R postgres:postgres /var/lib/postgresql/data
  else
    echo "[lazycat-entrypoint] empty data dir, no seed available — running initdb"
    find /var/lib/postgresql/data -mindepth 1 -delete
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data --auth=trust --encoding=UTF8 --locale=C.UTF-8"
  fi
fi

# --- jupyter home dir bootstrap ---
if [ -z "$(ls -A /home/jupyteruser 2>/dev/null)" ] && [ -d /opt/briefer/jupyter-home-seed ]; then
  echo "[lazycat-entrypoint] seeding /home/jupyteruser from prebuilt snapshot"
  cp -a /opt/briefer/jupyter-home-seed/. /home/jupyteruser/
  chown -R jupyteruser:jupyteruser /home/jupyteruser
fi

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
