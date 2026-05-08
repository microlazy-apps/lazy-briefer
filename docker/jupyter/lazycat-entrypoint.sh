#!/bin/sh
# jupyter service entrypoint — runs as root, chowns the bind-mounted
# /home/jupyteruser to jupyteruser before dropping privileges and
# launching the actual jupyter-server invocation.
#
# Without this, lazycat's bind mount comes in root-owned and the
# jupyter user can't mkdir /home/jupyteruser/.local/share/jupyter
# → PermissionError on first start.

set -eu

mkdir -p /home/jupyteruser/.local/share/jupyter
chown -R jupyteruser:jupyteruser /home/jupyteruser

exec runuser -u jupyteruser -- "$@"
