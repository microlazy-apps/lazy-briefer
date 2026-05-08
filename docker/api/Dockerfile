# Build context: full vendor/briefer tree (the workflow applies
# patches/api + patches/shared before invoking docker build).
#
# Mirrors upstream apps/api/Dockerfile but adds:
# - tini stays as PID 1 so node receives SIGTERM cleanly
# - lazycat-entrypoint.sh runs ahead of node to truncate
#   *_ENCRYPTION_KEY env vars + run `prisma migrate deploy`
# - postgresql-client is shipped so `prisma migrate` can talk to
#   the postgres-seed sibling service over the lazycat bridge

FROM node:18-slim AS base

ENV TURBO_TELEMETRY_DISABLED=1

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        openssl curl tini ca-certificates postgresql-client && \
    rm -rf /var/lib/apt/lists/*

FROM base AS builder
WORKDIR /app
RUN yarn global add turbo
COPY . .
RUN turbo prune @briefer/api --docker

FROM base AS installer
WORKDIR /app

COPY .gitignore .gitignore
COPY --from=builder /app/out/json/ .
COPY --from=builder /app/out/yarn.lock ./yarn.lock
RUN yarn install --network-timeout 1000000

COPY --from=builder /app/out/full/ .
COPY turbo.json turbo.json
RUN yarn turbo run build --filter=@briefer/api...

FROM base AS runner
WORKDIR /app

RUN groupadd -r expressjs && useradd -r -g expressjs expressjs \
    && mkdir -p /home/expressjs/Downloads /home/briefer/.config/briefer \
    && chown -R expressjs:expressjs /home/expressjs /home/briefer

COPY --from=installer /app .
RUN chown -R expressjs:expressjs /app/node_modules/@prisma/engines

# .lazycat-build/ is overlaid on top of the vendor build context by
# the release.yml workflow before `docker build` runs.
COPY .lazycat-build/api-entrypoint.sh /lazycat-entrypoint.sh
RUN chmod +x /lazycat-entrypoint.sh

USER expressjs

EXPOSE 8080

ENTRYPOINT ["tini", "--", "/lazycat-entrypoint.sh"]
CMD ["node", "--max-old-space-size=12000", "apps/api/dist/src/index.js"]
