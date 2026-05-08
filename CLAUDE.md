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
`v0.0.112`.

Bump:

```sh
git subtree pull --prefix=vendor/briefer \
  https://github.com/briefercloud/briefer.git vX.Y.Z --squash
git apply --check patches/*.patch -p1 --directory=vendor/briefer
```

## What the patch does

`patches/01-lazycat-base-url-and-shim.patch` is the only patch and
modifies four paths inside `vendor/briefer/`:

1. **`apps/api/src/embedding.ts`** — `new OpenAI({ apiKey })` →
   `new OpenAI({ apiKey, baseURL })`. Reads
   `OPENAI_BASE_URL` / `OPENAI_API_BASE` and falls back to undefined
   (which makes the SDK use `https://api.openai.com/v1`). Also
   honors `OPENAI_EMBEDDING_MODEL` so users on non-OpenAI endpoints
   can pick a compatible embedding model.
2. **`ai/api/llms.py`** — `ChatOpenAI(...)` gains `base_url=` plumbed
   from `OPENAI_BASE_URL` (or `OPENAI_API_BASE`). The Bedrock /
   Azure branches are untouched.
3. **`docker/lazycat-entrypoint.sh`** (new file) — wraps supervisord:
   - chown bind mounts (`/var/lib/postgresql/data`,
     `/home/jupyteruser`, `/home/briefer/.config/briefer`)
   - strip `localhost` from the IPv6 line of `/etc/hosts`
     (api → jupyter calls in Node 18+ otherwise hit `::1:8888`)
   - truncate `*_ENCRYPTION_KEY` env vars to 64 hex chars (lazycat's
     `stable_secret` is 128, briefer's `createCipheriv` wants 32)
   - copy `/opt/briefer/pg-seed` and `/opt/briefer/jupyter-home-seed`
     onto empty bind dirs on first boot
4. **`Dockerfile`** (new file at vendor root) — duplicates upstream's
   `docker/Dockerfile` and appends two stages:
   - run `initdb` + `init_db.sh` + `prisma migrate deploy` at build
     time, snapshot to `/opt/briefer/pg-seed` (saves users 30-60s
     on first boot)
   - install lazycat-entrypoint.sh as `CMD`

   Lives at vendor root because lazycat-ci's `lpk-build.yml` resolves
   `<docker-context>/Dockerfile` and we don't want to touch the org's
   shared CI for this one repo.

## Editing the patch

```sh
git apply patches/01-lazycat-base-url-and-shim.patch -p1 --directory=vendor/briefer
# edit vendor/briefer/...
git add -N vendor/briefer/Dockerfile vendor/briefer/docker/lazycat-entrypoint.sh
git diff --no-color --relative=vendor/briefer vendor/briefer/ \
  > patches/01-lazycat-base-url-and-shim.patch
git checkout HEAD -- \
  vendor/briefer/ai/api/llms.py \
  vendor/briefer/apps/api/src/embedding.ts
rm vendor/briefer/Dockerfile vendor/briefer/docker/lazycat-entrypoint.sh
git rm --cached vendor/briefer/Dockerfile vendor/briefer/docker/lazycat-entrypoint.sh
git apply --check patches/01-lazycat-base-url-and-shim.patch -p1 --directory=vendor/briefer
```

## Persistent volumes (critical)

Three binds — losing any one of them is data loss:

| Path on host | Path in container | Contents |
|---|---|---|
| `/lzcapp/var/persist/postgres` | `/var/lib/postgresql/data` | Briefer metadata + workspace state |
| `/lzcapp/var/persist/jupyter`  | `/home/jupyteruser`        | Notebook uploads + Jupyter state |
| `/lzcapp/var/persist/briefer`  | `/home/briefer/.config/briefer` | App config (`briefer.json`) |

JWT / encryption keys come from lazycat `stable_secret` (deterministic
across reinstalls).

## Release flow

1. Tag `vX.Y.Z` → `release.yml` builds + pushes ghcr image + ships
   lpk to the GitHub Release. `publish-appstore` succeeds once the app
   is bootstrapped.
2. First time only: trigger `bootstrap-app.yml` via Actions tab to
   register the app at lazycat developer center.
3. Validate on a real box (`lpk-manager install ...`) before
   bootstrapping (SKILL).

## Known gotchas

- **Image is huge** (~2.2GB after our build-time pg-seed; was already
  ~2.2GB upstream). First lazycat copy-image step takes time.
- **AI features need OpenAI-compatible endpoint**. Set
  `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_DEFAULT_MODEL_NAME`
  via deploy params at install — or change them per-workspace in
  briefer's UI later.
- **Schema explorer** runs an embedding pass on every new data
  source. If the configured endpoint refuses
  `text-embedding-3-small`, set `OPENAI_EMBEDDING_MODEL` to a model
  the endpoint supports (no UI for this yet — would need another
  patch to expose it in workspace settings).
- **start_period 600s** — first boot does seed-copy + setup.py +
  supervisord program startup; healthcheck must allow time.
