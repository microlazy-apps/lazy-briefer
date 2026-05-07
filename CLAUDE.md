# lazy-briefer — maintainer notes

Single-image retag wrapper of `briefercloud/briefer` for the lazycat
appstore. Mirrors lazy-pansou-web's pattern — no `vendor/` subtree, no
`patches/`. Repo is just `docker/Dockerfile` + lazycat metadata + thin
workflow shims.

## Layout

```
lazy-briefer/
├── docker/Dockerfile           single FROM, sha256-pinned
├── lazycat/
│   ├── lzc-build.yml           pkgout + icon + manifest + deploy-params
│   ├── lzc-manifest.template.yml
│   ├── lzc-deploy-params.yml
│   ├── package.template.yml
│   ├── appstore.yml
│   ├── icon.png
│   └── screenshots/
└── .github/workflows/
    ├── release.yml
    └── bootstrap-app.yml
```

## Architecture

The upstream `briefercloud/briefer:vX.Y.Z` image (~2.2GB) bundles
postgres + jupyter + ai + api + web + nginx and runs them under
supervisord. Nginx listens on 3000 inside the container; we map
lazycat's `main` upstream backend at `http://main:3000`.

setup.py auto-generates all needed secrets on first boot if absent;
we override its random generation with `stable_secret` so secrets
persist across reinstalls deterministically.

## Persistent volumes (critical)

Three binds — losing any one of them is data loss:

- `/var/lib/postgresql/data` — Briefer's metadata (workspaces, users,
  notebook DAG, encrypted data source credentials)
- `/home/jupyteruser` — every uploaded file, every Jupyter kernel
  state file
- `/home/briefer/.config/briefer` — `briefer.json` containing the
  active config (we override secrets via env vars but the file still
  exists)

## Bumping upstream

```sh
TAG=v0.0.112
docker pull briefercloud/briefer:$TAG
DIG=$(docker inspect --format '{{index .RepoDigests 0}}' briefercloud/briefer:$TAG | cut -d@ -f2)
sed -i "s|sha256:[a-f0-9]*|$DIG|" docker/Dockerfile
git commit -am "chore: bump briefer to $TAG"
```

If upstream changes the schema, prisma migrations run inside the
container on boot — nothing wrapper-side needs to change.

## Known gotchas

- **Image is huge** (~2.2GB). First lazycat copy-image step from ghcr
  takes time; users on slow links will see a long install bar.
- **AI features need `OPENAI_API_KEY`**. Without it, the AI service
  refuses to start and supervisord will keep restarting the `ai`
  program (logs noisy). The rest of briefer works fine. If we want
  to fully suppress that noise, future patch could conditionally
  drop `[program:ai]` from supervisord.conf when key is empty —
  requires an entrypoint hack since we don't vendor the source.
- **OracleInstantClient** is bundled but binary-only — pinning by
  digest avoids any rebuild issues.
- **start_period=180s** — first boot does prisma migrate + postgres
  init + AI venv setup; healthcheck must allow ~3min.

## Release flow

1. Tag `vX.Y.Z` → `release.yml` builds + pushes ghcr image + ships lpk
   to the GitHub Release. `publish-appstore` succeeds once the app is
   bootstrapped.
2. First time only: trigger `bootstrap-app.yml` via Actions tab to
   register the app at lazycat developer center.
3. Validate on a real box (`lpk-manager install ...`) before
   bootstrapping is recommended (SKILL): once submitted the package
   id + icon + screenshots lock in.
