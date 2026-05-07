#!/bin/bash
# Lazycat entrypoint shim for briefer.
#
# Lazycat binds host paths in as root-owned, but supervisord launches
# postgres / jupyter / api / web under non-root users. Re-own each bind
# to whoever the upstream image expects before handing off to
# supervisord (PID 1).

set -euo pipefail

# Postgres data dir — must be owned by the postgres user, mode 0700
# (otherwise pg_ctl refuses to start).
mkdir -p /var/lib/postgresql/data
chown -R postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

# Jupyter user home — uploaded files, kernel state, .ipynb_checkpoints.
mkdir -p /home/jupyteruser
chown -R jupyteruser:jupyteruser /home/jupyteruser

# Briefer api/web config dir — briefer.json with workspace secrets.
mkdir -p /home/briefer/.config/briefer
chown -R briefer:briefer /home/briefer/.config

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
