#!/bin/bash
# Lazycat entrypoint shim for briefer.
#
# Two issues to handle before exec'ing supervisord:
#
# 1. Lazycat binds host paths in as root-owned, but supervisord
#    launches each program under a non-root user. Re-own each bind to
#    its expected owner.
# 2. The upstream image initdb's /var/lib/postgresql/data at build
#    time, but bind-mounting an empty host dir on top hides that
#    initial cluster. Postgres then refuses to start with
#    "directory ... is empty". Detect an empty data dir and re-run
#    initdb. The PG_VERSION sentinel file is the conventional probe.

set -euo pipefail

# --- bind ownership fixups ---
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

mkdir -p /home/jupyteruser
chown -R jupyteruser:jupyteruser /home/jupyteruser

mkdir -p /home/briefer/.config/briefer
chown -R briefer:briefer /home/briefer/.config

# --- postgres data dir bootstrap ---
if [ ! -s /var/lib/postgresql/data/PG_VERSION ]; then
  echo "[lazycat-entrypoint] empty /var/lib/postgresql/data — running initdb"
  # initdb refuses to run if the dir is non-empty; clean any stray
  # bind-mount artefacts first (lost+found, .keep, etc.).
  find /var/lib/postgresql/data -mindepth 1 -delete
  su -s /bin/bash postgres -c \
    "/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data --auth=trust --encoding=UTF8 --locale=C.UTF-8"
fi

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
