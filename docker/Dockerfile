# syntax=docker/dockerfile:1
#
# Retag-only wrapper for briefercloud/briefer with a thin entrypoint
# shim. Lazycat binds host volumes into:
#
#   /var/lib/postgresql/data  → owned by root after bind
#   /home/jupyteruser         → owned by root after bind
#   /home/briefer/.config/briefer → owned by root after bind
#
# but supervisord launches postgres as `postgres`, jupyter as
# `jupyteruser`, and api/web as `briefer`. Without a fix the
# postgres process fails with `data directory has wrong ownership`
# and everything downstream blocks on "Waiting for postgres to be
# ready" forever. The shim chowns each bind to its expected owner
# before exec'ing supervisord.
#
# Bump procedure:
#   1) docker pull briefercloud/briefer:vX.Y.Z
#   2) DIG=$(docker inspect --format '{{index .RepoDigests 0}}' \
#          briefercloud/briefer:vX.Y.Z | cut -d@ -f2)
#   3) sed -i "s|sha256:[a-f0-9]\\+|$DIG|" docker/Dockerfile
#   4) bump the wrapper version + tag a release
FROM briefercloud/briefer@sha256:bdd19ccc8b9916d7665e175b1c417d13488af759d7df18b80c0bdbdf5311f1f8

COPY lazycat-entrypoint.sh /lazycat-entrypoint.sh
RUN chmod +x /lazycat-entrypoint.sh

ENTRYPOINT []
CMD ["/lazycat-entrypoint.sh"]
