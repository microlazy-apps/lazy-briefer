# --- Stage 1: build the seed --------------------------------------
# Spin up postgres locally during build, run init_db.sh + prisma
# migrate deploy, then snapshot /var/lib/postgresql/data into
# /opt/briefer/pg-seed. The seed gets copied onto an empty bind mount
# on first boot so users skip the long migrate stretch.
FROM pgvector/pgvector:pg15 AS seed-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Just the prisma source — no need to drag in apps/web or apps/api.
WORKDIR /app
COPY packages/database ./packages/database

# Install only the prisma CLI globally — `npx prisma migrate deploy`
# inside packages/database picks it up via PATH.
RUN npm install -g prisma@5

# init_db.sh ships in the upstream vendor tree.
COPY docker/init_db.sh /usr/local/bin/init_db.sh
RUN chmod +x /usr/local/bin/init_db.sh

# Bring up postgres → init_db.sh → vector ext → prisma migrate deploy
# → snapshot. All runs in a single RUN to keep the file system layer
# minimal.
RUN set -eux; \
    mkdir -p /var/lib/postgresql/data /opt/briefer; \
    chown -R postgres:postgres /var/lib/postgresql/data /opt/briefer; \
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/initdb -D /var/lib/postgresql/data --auth=trust --encoding=UTF8 --locale=C.UTF-8"; \
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data -l /tmp/pg-seed.log -w start"; \
    /usr/local/bin/init_db.sh; \
    su -s /bin/bash postgres -c "psql -d briefer -c 'CREATE EXTENSION IF NOT EXISTS vector;'"; \
    cd /app/packages/database && \
      DATABASE_URL="postgresql://briefer:briefer@localhost:5432/briefer?schema=public" \
      POSTGRES_PRISMA_URL="postgresql://briefer:briefer@localhost:5432/briefer?schema=public" \
      prisma migrate deploy --schema=prisma/schema.prisma; \
    su -s /bin/bash postgres -c \
      "/usr/lib/postgresql/15/bin/pg_ctl -D /var/lib/postgresql/data -m fast -w stop"; \
    cp -a /var/lib/postgresql/data /opt/briefer/pg-seed; \
    chown -R postgres:postgres /opt/briefer/pg-seed

# --- Stage 2: runtime -----------------------------------------------
FROM pgvector/pgvector:pg15

COPY --from=seed-builder --chown=postgres:postgres /opt/briefer/pg-seed /opt/briefer/pg-seed
# .lazycat-build/ is overlaid on top of the vendor build context by
# the release.yml workflow before `docker build` runs — see
# .github/workflows/release.yml `Overlay lazycat scripts` step.
COPY .lazycat-build/postgres-seed-entrypoint.sh /lazycat-entrypoint.sh
RUN chmod +x /lazycat-entrypoint.sh

# Same data dir contract as the upstream postgres image.
VOLUME /var/lib/postgresql/data

EXPOSE 5432

ENTRYPOINT ["/lazycat-entrypoint.sh"]
CMD ["postgres"]
