# lazy-briefer

懒猫微服 (LazyCat) lpk wrapper for [briefercloud/briefer](https://github.com/briefercloud/briefer) —
a self-hosted, open-source data notebook + dashboard tool.

## Install

```text
LazyCat 应用市场 → 搜索 "Briefer" → 安装
```

Then open `https://briefer.{your-box-domain}` in any browser. First
visit walks you through creating an admin account + workspace.

## What this is

Self-hosted Notion-style data notebooks with executable Python / SQL
cells, and dashboards built directly from the notebook outputs. Think
Hex / Deepnote / Mode, but you run it yourself.

Connectors out of the box: PostgreSQL, MySQL, BigQuery, Athena,
Redshift, Databricks, Oracle, CSV.

## AI assistant — any OpenAI-compatible provider

Each workspace's AI configuration is set in **Settings → AI**:

- **Assistant model** — free-text input (e.g. `gpt-4o`, `deepseek-chat`,
  `qwen-plus`, `llama3.2`)
- **AI API Base URL** — the endpoint (leave blank for OpenAI; or set
  `https://api.deepseek.com/v1`,
  `https://dashscope.aliyuncs.com/compatible-mode/v1`,
  `http://host.docker.internal:11434/v1`, …)
- **OpenAI API Key** — provider key, encrypted at rest
- **Test AI connection** — sends a 1-token chat completion to verify
  the combo works

The AI assistant is optional. Notebooks, dashboards, SQL editor, and
data connections all work without it.

> ⚠️ Many OpenAI-compatible providers (DeepSeek, Qwen, Ollama …) don't
> implement `/v1/embeddings`. The wrapper handles this gracefully:
> schema explorer + SQL block AI fall back to full-schema mode when
> embedding calls 404, so the assistant still works on those providers.

## Architecture

Vendored upstream + per-service Dockerfiles + per-service patches.

- `vendor/briefer/` — git subtree pinned to `briefercloud/briefer` at
  the upstream version tag (currently `v0.0.112`).
- `docker/<svc>/Dockerfile` — one per service we build ourselves
  (`postgres-seed`, `ai`, `api`, `web`, `main` (nginx)).
  `jupyter` uses upstream `apps/api/jupyter.Dockerfile` unmodified.
- `patches/<svc>/*.patch` — applied to the vendor tree before the
  matching service's docker build. Carries the per-workspace AI
  Base URL UI, the embedding-fallback patch, the prisma migration,
  and the `assistantApiBaseUrl` schema/types changes.

The lpk lazycat-manifest declares **6 sibling services** sharing the
default lazycat bridge network:

| service | image source | role |
|---|---|---|
| `postgres` | `docker/postgres-seed/` | pgvector + a build-time prisma seed copied onto the bind on first boot |
| `jupyter` | `vendor/briefer/apps/api/jupyter.Dockerfile` | unpatched upstream notebook executor |
| `ai` | `docker/ai/` | FastAPI bridge for OpenAI-compatible providers |
| `api` | `docker/api/` | Node API; runs `prisma migrate deploy` on every start |
| `web` | `docker/web/` | Next.js standalone build |
| `main` | `docker/main/` | nginx reverse-proxy on `:3000` (the public ingress) |

Lazycat pulls all 6 in parallel on first install; on upgrade only the
images whose source changed re-pull, the rest reuse the local cache.

## Persistent storage

| Path on host | Path in container | Contents |
|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | Briefer metadata + workspace state |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser`        | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | App config (`briefer.json`) |

JWT / encryption keys come from lazycat `stable_secret` (deterministic
across reinstalls).

## Build / release flow

- Push a `v*` tag → `release.yml` calls the local `lpk-multi-build.yml`
  reusable workflow which:
  1. matrix-builds 6 service images and pushes each to
     `ghcr.io/<repo>/<svc>:<version>`
  2. on a self-hosted lazycat runner, copies each image to
     `registry.lazycat.cloud` and renders the manifest with
     `LAZYCAT_IMAGE_<SVC>` env vars
  3. runs `lzc-cli project build` and uploads the .lpk artifact
- `publish-appstore` succeeds once the app is bootstrapped.
- First time only: trigger `bootstrap-app.yml` via Actions tab to
  register the app at lazycat developer center (also runs the matrix
  build).

## Bumping upstream

```sh
git subtree pull --prefix=vendor/briefer \
  https://github.com/briefercloud/briefer.git vX.Y.Z --squash
for d in patches/api patches/web patches/ai; do
  for p in "$d"/*.patch; do
    git apply --check "$p" -p1 --directory=vendor/briefer
  done
done
```

If a patched file moved or its surrounding context changed, regenerate
the patch (see `CLAUDE.md`).

## License

AGPL-3.0 (matching upstream).

- Upstream: <https://github.com/briefercloud/briefer>
- Wrapper: <https://github.com/microlazy-apps/lazy-briefer>
