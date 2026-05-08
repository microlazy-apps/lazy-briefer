# Build context: full vendor/briefer tree (workflow applies
# patches/web + patches/shared before invoking docker build).
#
# Mirrors upstream apps/web/Dockerfile but stays on node:18-slim
# instead of alpine — alpine + libc6-compat occasionally hits
# segfaults with the next/swc toolchain on lazycat's runner kernel,
# and the slim variant matches the api/ai images.

FROM node:18-slim AS base

ENV TURBO_TELEMETRY_DISABLED=1

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends openssl ca-certificates curl tini && \
    rm -rf /var/lib/apt/lists/*

FROM base AS builder
WORKDIR /app
RUN yarn global add turbo
COPY . .
RUN turbo prune @briefer/web --docker

FROM base AS installer
WORKDIR /app

COPY .gitignore .gitignore
COPY --from=builder /app/out/json/ .
COPY --from=builder /app/out/yarn.lock ./yarn.lock
RUN yarn install --network-timeout 1000000 --frozen-lockfile

COPY --from=builder /app/out/full/ .
COPY turbo.json turbo.json

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_API_WS_URL
ENV NEXT_PUBLIC_API_WS_URL=$NEXT_PUBLIC_API_WS_URL
ARG NEXT_PUBLIC_PUBLIC_URL
ENV NEXT_PUBLIC_PUBLIC_URL=$NEXT_PUBLIC_PUBLIC_URL

RUN yarn next telemetry disable
RUN yarn turbo run build --filter=@briefer/web...

FROM base AS runner
WORKDIR /app

RUN groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 -g nodejs nextjs

COPY --from=installer --chown=nextjs:nodejs /app/apps/web/next.config.js .
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/package.json .
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/.next/standalone ./
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/public ./apps/web/public
COPY --from=installer --chown=nextjs:nodejs /app/apps/web/start.sh ./apps/web/start.sh

USER nextjs

EXPOSE 4000

ENTRYPOINT ["tini", "--"]
CMD ["./apps/web/start.sh"]
