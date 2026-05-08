# syntax=docker/dockerfile:1
#
# Lazycat wrapper for briefercloud/briefer with first-boot perf tweaks.
#
# What this image adds on top of upstream:
#   1) lazycat-entrypoint.sh — chown bind mounts + seed empty data dirs
#   2) /opt/briefer/pg-seed — postgres data dir snapshot with the
#      briefer database, briefer role, pgvector extension, AND every
#      prisma migration already applied. First boot copies this into
#      the lazycat-mounted /var/lib/postgresql/data so users skip
#      the ~30-60s "Applying migration ..." stretch on a fresh install.
#   3) /opt/briefer/jupyter-home-seed — the original /home/jupyteruser
#      snapshot (upstream image has a venv there which bind-mounting
#      would otherwise hide).
#
# Bump procedure:
#   1) docker pull briefercloud/briefer:vX.Y.Z
#   2) DIG=$(docker inspect --format '{{index .RepoDigests 0}}' \
#         briefercloud/briefer:vX.Y.Z | cut -d@ -f2)
#   3) sed -i "s|sha256:[a-f0-9]\\+|$DIG|" docker/Dockerfile
#   4) bump the wrapper version + tag a release
FROM briefercloud/briefer@sha256:bdd19ccc8b9916d7665e175b1c417d13488af759d7df18b80c0bdbdf5311f1f8

# --- 1. snapshot the original /home/jupyteruser before we shadow it ---
RUN cp -a /home/jupyteruser /opt/briefer/jupyter-home-seed 2>/dev/null \
    || (mkdir -p /opt/briefer/jupyter-home-seed && true)

# --- 2. seed postgres: briefer role + DB + pgvector + prisma migrate ---
# At build time we boot postgres locally, run init_db.sh, then push the
# prisma schema, then snapshot the resulting data dir.
RUN set -eux; \
    mkdir -p /opt/briefer; \
    chown -R postgres:postgres /var/lib/postgresql/data; \
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data -l /tmp/pg-seed.log -w start"; \
    /usr/local/bin/init_db.sh; \
    su -s /bin/bash postgres -c "psql -d briefer -c 'CREATE EXTENSION IF NOT EXISTS vector;'"; \
    cd /app/packages/database && \
      DATABASE_URL="postgresql://briefer:briefer@localhost:5432/briefer?schema=public" \
      POSTGRES_PRISMA_URL="postgresql://briefer:briefer@localhost:5432/briefer?schema=public" \
      npx prisma migrate deploy; \
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data -m fast -w stop"; \
    cp -a /var/lib/postgresql/data /opt/briefer/pg-seed; \
    chown -R postgres:postgres /opt/briefer/pg-seed

# --- 3. lazycat entrypoint shim ---
COPY lazycat-entrypoint.sh /lazycat-entrypoint.sh
RUN chmod +x /lazycat-entrypoint.sh

ENTRYPOINT []
CMD ["/lazycat-entrypoint.sh"]
