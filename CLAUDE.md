# lazy-briefer — maintainer notes

LazyCat lpk wrapper for `briefercloud/briefer`. Vendor + per-service
patches + per-service Dockerfiles.

## Layout

```
lazy-briefer/
├── vendor/briefer/                git subtree pinned to upstream tag
├── patches/
│   ├── api/01-base-url-and-prisma.patch
│   ├── web/01-settings-ui.patch
│   └── ai/01-base-url.patch
├── docker/
│   ├── postgres-seed/Dockerfile + lazycat-entrypoint.sh
│   ├── api/Dockerfile + lazycat-entrypoint.sh
│   ├── web/Dockerfile
│   ├── ai/Dockerfile
│   └── main/Dockerfile             (nginx)
├── lazycat/                       manifest, build, package, appstore
└── .github/workflows/
    ├── lpk-multi-build.yml        reusable matrix build (6 images)
    ├── release.yml                tag-driven, calls lpk-multi-build + publish
    └── bootstrap-app.yml          manual, calls lpk-multi-build + bootstrap
```

## Vendor pin

`vendor/briefer/` is a git subtree of `briefercloud/briefer` at tag
`v0.0.112`. To bump:

```sh
git subtree pull --prefix=vendor/briefer \
  https://github.com/briefercloud/briefer.git vX.Y.Z --squash

# verify each per-service patch still applies cleanly
for d in patches/api patches/web patches/ai; do
  for p in "$d"/*.patch; do
    git apply --check "$p" -p1 --directory=vendor/briefer || echo "FAIL: $p"
  done
done
```

## Service split

| service | image | upstream / our build | role |
|---|---|---|---|
| `postgres` | `${LAZYCAT_IMAGE_POSTGRES_SEED}` | `docker/postgres-seed/` | pgvector + build-time prisma seed |
| `jupyter` | `${LAZYCAT_IMAGE_JUPYTER}` | `docker/jupyter/` (mirrors upstream `apps/api/jupyter.Dockerfile` on bookworm) | notebook executor (no patches) |
| `ai` | `${LAZYCAT_IMAGE_AI}` | `docker/ai/` + `patches/ai/` | LLM bridge (per-workspace base_url) |
| `api` | `${LAZYCAT_IMAGE_API}` | `docker/api/` + `patches/api/` | Node API + prisma migrate at boot |
| `web` | `${LAZYCAT_IMAGE_WEB}` | `docker/web/` + `patches/web/` | Next.js standalone |
| `main` | `${LAZYCAT_IMAGE_MAIN}` | `docker/main/` (nginx:1.27) | public ingress on `:3000` |

Inter-service URLs use lazycat's default DNS — sibling services
resolve by service name (`http://api:8080`, `http://jupyter:8888`,
etc.). The application's public health check hits `main:3000/`.

### postgres-seed

Two-stage Dockerfile:
1. `seed-builder` — pgvector/pgvector:pg15 + nodejs, brings up
   postgres locally, runs `init_db.sh` + `CREATE EXTENSION vector` +
   `prisma migrate deploy`, then snapshots `/var/lib/postgresql/data`
   to `/opt/briefer/pg-seed`.
2. `runtime` — same pgvector base, copies the seed, ships
   `lazycat-entrypoint.sh` that copies seed → bind on first boot
   (`PG_VERSION` missing) and exec's `docker-entrypoint.sh`.

The seed is regenerated whenever the `packages/database/prisma/`
contents change — bump the api patch's migration timestamp and the
postgres-seed image cache will invalidate naturally.

### api

`prisma migrate deploy` runs on every container start. Idempotent —
only migrations not yet recorded in `_prisma_migrations` apply. This
handles upgrades where the postgres-seed image is older than the api
image.

The encryption-key truncation (128-hex stable_secret → 64) lives in
`docker/api/lazycat-entrypoint.sh` because only api consumes those
keys.

### web

No runtime patches. Build-time patch only: free-text model picker +
AI Base URL field + Test button (see `patches/web/01-settings-ui.patch`).

### ai

Build-time patch makes `initialize_llm` accept `openai_api_base` and
`SQLEditInputData` / `PythonEditInputData` accept `openaiApiBase` from
the api request body — that's how per-workspace base URL works
end-to-end. No runtime config needed; the install-time AI
deploy-params were dropped earlier (see git log
`3cefe14 chore: drop deploy params + container OPENAI_* envs`).

### main (nginx)

Just `nginx:1.27-alpine` + the upstream `nginx/nginx.conf` baked in.
The conf already targets `web:4000` and `api:8080`, which are the
sibling service names lazycat resolves via the bridge network.

## What each patch does

### `patches/ai/01-base-url.patch`
- `ai/api/llms.py` — `initialize_llm(..., openai_api_base=None)` →
  `ChatOpenAI(base_url=...)` (priority: arg > env > SDK default)
- `ai/api/app.py` — `SQLEditInputData` / `PythonEditInputData` accept
  `openaiApiBase`; pass to `initialize_llm`

### `patches/api/01-base-url-and-prisma.patch`
- `apps/api/src/v1/workspaces/workspace/index.ts` — new
  `POST /v1/workspaces/:id/ai-test` endpoint
- `apps/api/src/embedding.ts` — accepts `apiBaseUrl?`,
  `OPENAI_EMBEDDING_MODEL` env, **falls back to null on 404 / network
  errors** so providers without `/v1/embeddings` (DeepSeek, Qwen,
  Ollama …) don't kill SQL Edit-with-AI
- `apps/api/src/datasources/structure.ts` — passes
  `workspace.assistantApiBaseUrl` into `createEmbedding`
- `apps/api/src/yjs/v2/executor/ai/{sql,python}.ts` — pass
  `assistantApiBaseUrl` through `sqlEditStreamed` / `pythonEditStreamed`
- `apps/api/src/ai-api.ts` — forward `openaiApiBase` to ai service
- `apps/api/src/python/query/sqlalchemy.ts` — force
  `client_encoding=utf8` on the psql engine (otherwise non-ASCII
  output crashes with `'ascii' codec can't decode byte`)
- `packages/database/prisma/schema.prisma` —
  `Workspace.assistantApiBaseUrl String?`
- `packages/database/prisma/migrations/20260508120000_*/migration.sql`
- `packages/database/src/workspaces.ts` — `updateWorkspace` persists
  the new field
- `packages/types/src/index.ts` — `WorkspaceEditFormValues` accepts
  the field (zod nullable so `''` clears the override)

### `patches/web/01-settings-ui.patch`
- `apps/web/src/pages/workspaces/[workspaceId]/settings/index.tsx`
  - replace the disabled `<select>` (model picker) with a free-text
    input — any OpenAI-compatible model name
  - add an "AI API Base URL" section
  - add a "Test AI connection" button → calls `/ai-test` and shows
    success/error inline
- `packages/types/src/index.ts` — same hunk as the api patch (web
  builds also need the type) so the patches are not jointly
  applicable; each runs against a fresh vendor checkout in its own
  matrix job.

## Editing a patch

```sh
# pick the service whose patch you want to edit, e.g. api
git apply patches/api/01-base-url-and-prisma.patch -p1 --directory=vendor/briefer

# edit vendor/briefer/...

# if you added a new file, mark it intent-to-add so git diff sees it
git add -N vendor/briefer/<new-file>

git diff --no-color --relative=vendor/briefer vendor/briefer/ \
  > patches/api/01-base-url-and-prisma.patch

# restore vendor pristine — only the files this patch touches
git checkout HEAD -- vendor/briefer/apps/api vendor/briefer/packages
git rm --cached vendor/briefer/packages/database/prisma/migrations/20260508120000_*/migration.sql 2>/dev/null || true
rm -rf vendor/briefer/packages/database/prisma/migrations/20260508120000_*

# verify
git apply --check patches/api/01-base-url-and-prisma.patch -p1 --directory=vendor/briefer
```

The same pattern works for `patches/web/` and `patches/ai/`. When
adding a new patch file, drop it under the appropriate
`patches/<svc>/` subdir — the workflow picks up `*.patch` in there
automatically.

## Manifest extras (lazycat/lzc-manifest.template.yml)

- `application.health_check.start_period: 300s` — allows the first
  pg-seed copy + AI venv warm-up + jupyter start
- `PYTHONUTF8=1` + `PYTHONIOENCODING=utf-8` + `LANG=C.UTF-8` +
  `LC_ALL=C.UTF-8` on api + ai — node:18-slim's C locale otherwise
  leaves Python in ASCII filesystem encoding, blowing up on any
  non-ASCII byte in SQL output
- `POSTGRES_CONNECTION_LIMIT=50` + `POSTGRES_POOL_TIMEOUT=30` on api
  — 10/5 default starves under schema explorer load
- All AES-256 keys (`*_ENCRYPTION_KEY`, `LOGIN_JWT_SECRET`,
  `AUTH_JWT_SECRET`, …) come from `stable_secret` so reinstalls
  preserve encrypted data
- `depends_on:` is start-order only (lazycat doesn't honor
  `condition: service_healthy` in v0.1 manifests). Crash-on-startup
  is OK because lazycat restarts services until the dependencies
  come up — api's `prisma migrate deploy` typically gets one
  postgres-not-ready bounce on a cold start.

## Persistent volumes

| Path on host | Path in container | Service | Contents |
|---|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | postgres | Briefer metadata + workspace state |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser` | jupyter | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | api | App config |

## Release flow

1. Tag `vX.Y.Z` → `release.yml` invokes `lpk-multi-build.yml`:
   - 6 parallel `docker/build-push-action@v6` jobs push to
     `ghcr.io/<repo>/<svc>:<version>` (matrix on `service.name`)
   - self-hosted job copies each digest to lazycat registry,
     renders the manifest with `LAZYCAT_IMAGE_<SVC>` envs, runs
     `lzc-cli project build`, uploads the lpk
   - then publish-appstore submits the lpk update
2. First time only: dispatch `bootstrap-app.yml` via Actions tab —
   builds the lpk and submits the create-app + first-version review.
3. **Validate on a real box** (`lpk-manager install …`) before
   bootstrapping — bootstrap is one-way (locks app id + icon +
   screenshots).

## Known gotchas

- **api → postgres race on cold start.** api boots faster than
  postgres-seed finishes copying its 50MB seed onto the bind. The
  container exits non-zero, lazycat restarts it, and the second
  attempt succeeds. We accept the bounce instead of a sleep loop.
- **DeepSeek / Qwen don't ship `/v1/embeddings`.** The fallback in
  embedding.ts means SQL Edit-with-AI still works (full-schema
  mode); schema explorer's vector-search-by-question gracefully
  degrades.
- **First boot ≥ 300s start_period.** Don't shrink without testing
  the pg-seed copy on slow disks.
- **Workspace's `assistantApiBaseUrl` UI uses `onBlur` to save**.
  Users have to click off the field to commit.

## Open follow-ups (not blocking the split)

- [ ] Decide the bump cadence: do we bump VERSION on every change to
      `docker/<svc>/`, or only when patches/ changes? Today every
      tag pushes 6 fresh images even if 5 of them are byte-identical
      to the prior tag — the GHA cache helps but the lazycat copy-
      image step still runs 6 times.
- [ ] Snapshotting jupyter's `/home/jupyteruser` is no longer needed
      now that jupyter runs as its own container. Confirm a fresh
      install no longer requires a seed copy and clean up
      `lazycat-entrypoint.sh` references in the legacy CLAUDE.md
      history once enough data is in.
