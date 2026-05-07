# lazy-briefer

懒猫微服 (LazyCat) lpk wrapper for [briefercloud/briefer](https://github.com/briefercloud/briefer) —
a self-hosted, open-source data notebook + dashboard tool.

## Install

```text
LazyCat 应用市场 → 搜索 "Briefer" → 安装（可选填 OPENAI_API_KEY）
```

Then open `https://briefer.{your-box-domain}` in any browser. The first
visit walks you through creating an admin account + workspace.

## What this is

Self-hosted Notion-style data notebooks with executable Python / SQL
cells, and dashboards built directly from the notebook outputs. Think
Hex / Deepnote / Mode, but you run it yourself.

Connectors out of the box: PostgreSQL, MySQL, BigQuery, Athena,
Redshift, Databricks, Oracle, CSV.

## Architecture

This wrapper is a single retag of `briefercloud/briefer:v0.0.112`
(pinned by sha256 digest). The upstream image bundles every service
with supervisord:

- Postgres 15 + pgvector (internal app metadata)
- Jupyter Server (sandboxed Python execution)
- AI service (FastAPI)
- API (Node.js)
- Web (Next.js)
- nginx (listens on 3000, fronts web:4000 + api:8080)

So we only ship a `docker/Dockerfile` with one `FROM` line plus the
lazycat manifest. No upstream source vendored, no patches applied.

## Persistent storage

| Path on host | Path in container | Contents |
|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | Briefer's internal Postgres |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser`        | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | App config (auto-generated secrets) |

JWT / encryption keys are derived from LazyCat `stable_secret` so they
survive container restarts and reinstalls without losing data.

## Optional AI

Provide `OPENAI_API_KEY` at install (deploy params) to enable the AI
assistant (SQL completion, ask-your-data). Notebooks, dashboards, SQL
editor, and data connections all work without it.

## Build / release flow

Standard `microlazy-apps` lazycat-ci pattern:

- Push a `v*` tag → `release.yml` builds and publishes the lpk to
  the GitHub Release and the lazycat appstore.
- First-time submission: run `bootstrap-app.yml` once via the Actions
  tab.

## Bumping upstream

```sh
TAG=v0.0.112  # whatever the new upstream tag is
docker pull briefercloud/briefer:$TAG
DIG=$(docker inspect --format '{{index .RepoDigests 0}}' briefercloud/briefer:$TAG | cut -d@ -f2)
sed -i "s|sha256:[a-f0-9]*|$DIG|" docker/Dockerfile
git commit -am "chore: bump upstream to $TAG ($DIG)"
git tag vX.Y.Z && git push origin main vX.Y.Z
```

## License

AGPL-3.0 (matching upstream).

- Upstream: <https://github.com/briefercloud/briefer>
- Wrapper: <https://github.com/microlazy-apps/lazy-briefer>
