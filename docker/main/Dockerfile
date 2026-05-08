FROM nginx:1.27-alpine

# Upstream nginx.conf already targets web:4000 + api:8080. Lazycat's
# default network places sibling services on the same DNS namespace
# so `web` and `api` resolve to the other containers without extra
# config.
COPY nginx/nginx.conf /etc/nginx/nginx.conf

# Briefer expects the public ingress on :3000 (matches upstream
# docker-compose.yaml) — keep that contract so existing
# lzc-manifest backend pointers don't change.
EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
