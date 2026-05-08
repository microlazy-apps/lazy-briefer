# Build context: full vendor/briefer tree (workflow applies
# patches/ai before invoking docker build).
#
# Mirrors upstream ai/Dockerfile. Build context is the repo root so
# we can also drop in shared assets if needed; pip only sees ai/.

FROM python:3.10-slim-bullseye

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        default-libmysqlclient-dev \
        gcc \
        build-essential \
        pkg-config \
        curl \
        ca-certificates \
        tini && \
    rm -rf /var/lib/apt/lists/*

ENV PYTHONUNBUFFERED=True
ENV PYTHONUTF8=1
ENV PYTHONIOENCODING=utf-8

WORKDIR /app
COPY ai/. ./

RUN pip install --no-cache-dir -r requirements.txt

ENV PORT=8000
EXPOSE 8000

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", "uvicorn api.app:app --host 0.0.0.0 --port ${PORT}"]
