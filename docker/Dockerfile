# syntax=docker/dockerfile:1
#
# Retag-only wrapper for briefercloud/briefer.
#
# We pin by sha256 digest instead of by :v tag — the digest is reproducible
# and lets `git log` track upstream version bumps explicitly.
#
# Bump procedure:
#   1) docker pull briefercloud/briefer:vX.Y.Z
#   2) docker inspect --format '{{index .RepoDigests 0}}' briefercloud/briefer:vX.Y.Z
#   3) update the FROM line below
#   4) bump the wrapper version + tag a release
FROM briefercloud/briefer@sha256:bdd19ccc8b9916d7665e175b1c417d13488af759d7df18b80c0bdbdf5311f1f8
