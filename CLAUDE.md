# lazy-briefer — maintainer notes

LazyCat lpk wrapper for `briefercloud/briefer`. Vendor + patch model.

## Layout

```
lazy-briefer/
├── vendor/briefer/             git subtree pinned to upstream tag
├── patches/
│   └── 01-lazycat-base-url-and-shim.patch
├── lazycat/                    manifest, build, deploy-params, appstore
└── .github/workflows/
```

## Vendor pin

`vendor/briefer/` is a git subtree of `briefercloud/briefer` at tag
`v0.0.112`. To bump:

```sh
git subtree pull --prefix=vendor/briefer \
  https://github.com/briefercloud/briefer.git vX.Y.Z --squash
git apply --check patches/*.patch -p1 --directory=vendor/briefer
```

## What the patch does

`patches/01-lazycat-base-url-and-shim.patch` is the only patch and
modifies / adds these paths inside `vendor/briefer/`:

### Per-workspace AI provider

- `packages/database/prisma/schema.prisma` — add
  `Workspace.assistantApiBaseUrl String?`
- `packages/database/prisma/migrations/20260508120000_*/migration.sql`
  — `ALTER TABLE Workspace ADD COLUMN assistantApiBaseUrl TEXT`
- `packages/database/src/workspaces.ts` — `updateWorkspace` persists
  the new field; `getWorkspaceWithSecrets` includes it
- `packages/types/src/index.ts` — `WorkspaceEditFormValues` accepts
  the field (zod nullable so `''` clears the override)
- `apps/web/src/pages/workspaces/[workspaceId]/settings/index.tsx`
  - replace the disabled `<select>` (model picker) with a free-text
    input — any OpenAI-compatible model name
  - add an "AI API Base URL" section
  - add a "Test AI connection" button → calls `/ai-test` and shows
    success/error inline
- `apps/api/src/v1/workspaces/workspace/index.ts` — new
  `POST /v1/workspaces/:id/ai-test` endpoint that does a 1-token
  chat.completions roundtrip against the saved config
- `apps/api/src/embedding.ts`
  - `createEmbedding` accepts `apiBaseUrl?` (workspace > env > SDK
    default)
  - honor `OPENAI_EMBEDDING_MODEL` env so endpoints that don't ship
    `text-embedding-3-small` can pick a compatible model
  - **Fallback to null on 404 / network errors** so providers without
    `/v1/embeddings` (DeepSeek, Qwen, Ollama …) don't kill SQL
    Edit-with-AI; the caller falls back to full-schema mode
- `apps/api/src/datasources/structure.ts` — pass
  `workspace.assistantApiBaseUrl` into `createEmbedding`
- `apps/api/src/yjs/v2/executor/ai/sql.ts` /
  `apps/api/src/yjs/v2/executor/ai/python.ts` — pass
  `assistantApiBaseUrl` through `sqlEditStreamed` /
  `pythonEditStreamed`
- `apps/api/src/ai-api.ts` — `sqlEditStreamed` / `pythonEditStreamed`
  forward `openaiApiBase` in the POST body to the ai service
- `ai/api/app.py` — `SQLEditInputData` / `PythonEditInputData` accept
  `openaiApiBase`; pass to `initialize_llm`
- `ai/api/llms.py` — `initialize_llm(..., openai_api_base=None)` →
  `ChatOpenAI(base_url=...)` (priority: arg > env > SDK default)

### Image build (Dockerfile at vendor root, not docker/)

- new file `vendor/briefer/Dockerfile` — duplicates upstream's
  `docker/Dockerfile` and appends:
  - build-time `initdb` + `init_db.sh` + `prisma migrate deploy`
    snapshot to `/opt/briefer/pg-seed` (saves first-boot ~30-60s)
  - copy upstream `/home/jupyteruser` baseline to
    `/opt/briefer/jupyter-home-seed` before any bind hides it
  - install `lazycat-entrypoint.sh` as `CMD`

  Lives at vendor root because lazycat-ci's `lpk-build.yml` resolves
  `<docker-context>/Dockerfile` and we don't want to touch the org's
  shared CI workflow for one repo.

### Entrypoint shim — `vendor/briefer/docker/lazycat-entrypoint.sh`

Runs before supervisord:

- chown bind mounts (`/var/lib/postgresql/data`,
  `/home/jupyteruser`, `/home/briefer/.config/briefer`) to their
  expected non-root users
- strip `localhost` from the IPv6 line of `/etc/hosts` via
  `cat`-truncate (sed -i fails EXDEV on docker-managed `/etc/hosts`)
  so api → jupyter axios calls don't try `::1:8888`
- truncate `*_ENCRYPTION_KEY` env vars to 64 hex chars (lazycat's
  `stable_secret` is 128, briefer's `createCipheriv` wants 32)
- copy `/opt/briefer/pg-seed` → `/var/lib/postgresql/data` on first
  boot (when `PG_VERSION` missing)
- copy `/opt/briefer/jupyter-home-seed` → `/home/jupyteruser` on
  first boot (when empty)

## Manifest extras (lazycat/lzc-manifest.template.yml)

- `start_period: 600s` for both application + docker healthcheck so
  the long first boot (cp + supervisord program startup) doesn't get
  killed
- `PYTHONUTF8=1` + `PYTHONIOENCODING=utf-8` + `LANG=C.UTF-8` +
  `LC_ALL=C.UTF-8` — node:18-slim's C locale otherwise leaves
  Python in ASCII filesystem encoding, blowing up on any non-ASCII
  byte in SQL output
- `POSTGRES_CONNECTION_LIMIT=50` + `POSTGRES_POOL_TIMEOUT=30` —
  10/5 default starves under schema explorer load
- All AES-256 keys (`*_ENCRYPTION_KEY`, `LOGIN_JWT_SECRET`,
  `AUTH_JWT_SECRET`, …) come from `stable_secret` so reinstalls
  preserve encrypted data

## Deploy params (lazycat/lzc-deploy-params.yml)

Optional `OPENAI_API_KEY` / `OPENAI_BASE_URL` /
`OPENAI_DEFAULT_MODEL_NAME` to seed AI for new workspaces. Per-workspace
overrides via UI win over these.

## Editing the patch

```sh
git apply patches/01-lazycat-base-url-and-shim.patch -p1 --directory=vendor/briefer
# edit vendor/briefer/...
git add -N vendor/briefer/Dockerfile \
           vendor/briefer/docker/lazycat-entrypoint.sh \
           vendor/briefer/packages/database/prisma/migrations/20260508120000_*/migration.sql
git diff --no-color --relative=vendor/briefer vendor/briefer/ \
  > patches/01-lazycat-base-url-and-shim.patch

# restore vendor pristine
git checkout HEAD -- \
  vendor/briefer/ai/api/llms.py \
  vendor/briefer/ai/api/app.py \
  vendor/briefer/apps/api/src/ai-api.ts \
  vendor/briefer/apps/api/src/datasources/structure.ts \
  vendor/briefer/apps/api/src/embedding.ts \
  vendor/briefer/apps/api/src/v1/workspaces/workspace/index.ts \
  vendor/briefer/apps/api/src/yjs/v2/executor/ai/sql.ts \
  vendor/briefer/apps/api/src/yjs/v2/executor/ai/python.ts \
  'vendor/briefer/apps/web/src/pages/workspaces/[workspaceId]/settings/index.tsx' \
  vendor/briefer/packages/database/prisma/schema.prisma \
  vendor/briefer/packages/database/src/workspaces.ts \
  vendor/briefer/packages/types/src/index.ts
rm vendor/briefer/Dockerfile vendor/briefer/docker/lazycat-entrypoint.sh
rm -rf vendor/briefer/packages/database/prisma/migrations/20260508120000_*
git rm --cached vendor/briefer/Dockerfile \
                vendor/briefer/docker/lazycat-entrypoint.sh \
                vendor/briefer/packages/database/prisma/migrations/20260508120000_*/migration.sql

git apply --check patches/01-lazycat-base-url-and-shim.patch -p1 --directory=vendor/briefer
```

## Persistent volumes (critical)

| Path on host | Path in container | Contents |
|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | Briefer metadata + workspace state |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser`        | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | App config |

## Release flow

1. Tag `vX.Y.Z` → `release.yml` builds + pushes ghcr image + ships
   lpk to the GitHub Release. `publish-appstore` succeeds once the app
   is bootstrapped.
2. First time only: trigger `bootstrap-app.yml` via Actions tab to
   register the app at lazycat developer center.
3. **Validate on a real box** (`lpk-manager install …`) before
   bootstrapping — bootstrap is one-way (locks app id + icon +
   screenshots).

## Known gotchas

- **Image is huge (~2.2GB+)**. First lazycat copy-image step is slow.
  ghcr blob SAS expires after ~5 min during copy → lzc-cli fails →
  GitHub Actions auto-retries the `build / build` job; usually
  succeeds on retry.
- **DeepSeek / Qwen don't ship `/v1/embeddings`**. The fallback in
  embedding.ts means SQL Edit-with-AI still works (full-schema mode);
  schema explorer's vector-search-by-question gracefully degrades.
- **First boot needs ≥ 600s start_period**. Don't shrink without
  testing `cp -a /opt/briefer/pg-seed → bind dir` on slow disks.
- **Workspace's `assistantApiBaseUrl` UI uses `onBlur` to save**.
  Users have to click off the field to commit.
