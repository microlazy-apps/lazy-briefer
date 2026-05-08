FROM nginx:1.27-alpine

# Upstream nginx.conf already targets web:4000 + api:8080. Lazycat's
# default network places sibling services on the same DNS namespace
# so `web` and `api` resolve to the other containers without extra
# config.
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# lazycat docker network is dual-stack (enable_ipv6: true); upstream's
# `server api:8080` lines resolve to BOTH IPv4 and IPv6 records, but
# briefer's Node api process only listens on IPv4 — connections
# routed to the IPv6 ULA endpoint return 502 'upstream prematurely
# closed connection'. Inject a resolver with ipv6=off and switch the
# static `upstream { server <name>:port }` blocks to dynamic
# variable-based proxy_pass so the resolver actually applies.
RUN set -eux; \
    sed -i \
      -e '/^http {$/a\    resolver 127.0.0.11 ipv6=off valid=10s;' \
      -e '/upstream web {/,/^    }$/d' \
      -e '/upstream api {/,/^    }$/d' \
      /etc/nginx/nginx.conf; \
    sed -i \
      -e 's|proxy_pass http://api/|set $upstream_api "api:8080"; proxy_pass http://$upstream_api/|g' \
      -e 's|proxy_pass http://web/|set $upstream_web "web:4000"; proxy_pass http://$upstream_web/|g' \
      -e 's|proxy_pass http://api;|set $upstream_api "api:8080"; proxy_pass http://$upstream_api;|g' \
      -e 's|proxy_pass http://web;|set $upstream_web "web:4000"; proxy_pass http://$upstream_web;|g' \
      /etc/nginx/nginx.conf

# Briefer expects the public ingress on :3000 (matches upstream
# docker-compose.yaml) — keep that contract so existing
# lzc-manifest backend pointers don't change.
EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
