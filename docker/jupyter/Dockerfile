# Build context: vendor/briefer/apps/api
#
# Mirrors upstream apps/api/jupyter.Dockerfile but:
# - bumps base from python:3.9-slim → python:3.10-slim-bookworm
#   (3.9-slim now resolves to bookworm anyway, so we'd hit bookworm
#   either way — explicit is clearer)
# - renames libaio1 → libaio1t64 (debian bookworm rename;
#   `apt-get install libaio1` fails with E: Unable to locate package)
#
# Everything else (Oracle Instant Client, jupyter_briefer_extension,
# example-data) is identical to upstream so the runtime contract
# matches the upstream image.

FROM python:3.10-slim-bookworm

WORKDIR /usr/src/app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpq-dev \
        r-base \
        python3-dev \
        graphviz \
        libgraphviz-dev \
        default-libmysqlclient-dev \
        build-essential \
        pkg-config \
        jq \
        git \
        gdal-bin \
        libgdal-dev \
        curl \
        ca-certificates \
        libaio1t64 \
        alien \
        && rm -rf /var/lib/apt/lists/*

#### ORACLE INSTANT CLIENT ####
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        curl -o /tmp/oracle-instantclient-basiclite.rpm https://download.oracle.com/otn_software/linux/instantclient/1924000/oracle-instantclient19.24-basiclite-19.24.0.0.0-1.aarch64.rpm && \
        alien -i /tmp/oracle-instantclient-basiclite.rpm && \
        rm /tmp/oracle-instantclient-basiclite.rpm; \
    elif [ "$TARGETARCH" = "amd64" ]; then \
        curl -o /tmp/oracle-instantclient-basiclite.rpm https://download.oracle.com/otn_software/linux/instantclient/2340000/oracle-instantclient-basic-23.4.0.24.05-1.el8.x86_64.rpm && \
        alien -i /tmp/oracle-instantclient-basiclite.rpm && \
        rm /tmp/oracle-instantclient-basiclite.rpm; \
    else \
        echo "Unsupported architecture: $TARGETARCH"; \
        exit 1; \
    fi

ENV LD_LIBRARY_PATH="/usr/lib/oracle/19.24/client64/lib:/usr/lib/oracle/23.4/client64/lib:${LD_LIBRARY_PATH}"
ENV ORACLE_HOME="/usr/lib/oracle/19.24/client64:/usr/lib/oracle/23.4/client64"
#### END ORACLE INSTANT CLIENT ####

ENV CPLUS_INCLUDE_PATH=/usr/include/gdal
ENV C_INCLUDE_PATH=/usr/include/gdal

ARG JUPYTER_REQUIREMENTS_FILE=jupyter-requirements.txt
COPY $JUPYTER_REQUIREMENTS_FILE ./requirements.txt

RUN pip install --upgrade pip && \
    pip install --no-cache-dir jupyter_server ipykernel && \
    pip install --no-cache-dir -r requirements.txt

COPY ./jupyter_briefer_extension /usr/src/jupyter_briefer_extension
RUN pip install /usr/src/jupyter_briefer_extension && \
    jupyter server extension enable jupyter_briefer_extension --sys-prefix

COPY ./example-data/ /usr/src/example-data

RUN useradd -m -d /home/jupyteruser jupyteruser && \
    groupadd -g 1001 briefer && usermod -aG briefer jupyteruser

USER jupyteruser
WORKDIR /home/jupyteruser

EXPOSE 8888
