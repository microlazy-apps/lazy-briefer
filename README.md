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

Vendored upstream + a single patch.

- `vendor/briefer/` — git subtree pinned to `briefercloud/briefer` at
  the upstream version tag (currently `v0.0.112`).
- `patches/01-lazycat-base-url-and-shim.patch` — applied at CI build
  time. Adds the per-workspace AI Base URL field, an entrypoint shim
  for chowns / IPv6 / encryption-key length / pg-seed copy, and
  build-time pg-seed snapshots.

The image still ships the upstream architecture: Postgres 15 +
pgvector, Jupyter Server, AI service (FastAPI), API (Node), Web
(Next.js), nginx — all started by supervisord, behind nginx on port
3000.

## Persistent storage

| Path on host | Path in container | Contents |
|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | Briefer metadata + workspace state |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser`        | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | App config (`briefer.json`) |

JWT / encryption keys come from lazycat `stable_secret` (deterministic
across reinstalls).

## Build / release flow

Standard `microlazy-apps` lazycat-ci pattern:

- Push a `v*` tag → `release.yml` builds + pushes ghcr image + ships
  lpk to the GitHub Release. `publish-appstore` succeeds once the app
  is bootstrapped.
- First time only: trigger `bootstrap-app.yml` via Actions tab to
  register the app at lazycat developer center.

## Bumping upstream

```sh
git subtree pull --prefix=vendor/briefer \
  https://github.com/briefercloud/briefer.git vX.Y.Z --squash
git apply --check patches/*.patch -p1 --directory=vendor/briefer
```

If a patched file moved or its surrounding context changed, regenerate
the patch (see `CLAUDE.md`).

## License

AGPL-3.0 (matching upstream).

- Upstream: <https://github.com/briefercloud/briefer>
- Wrapper: <https://github.com/microlazy-apps/lazy-briefer>
