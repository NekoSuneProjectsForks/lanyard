# All-in-one Lanyard image.
#
# Builds the Elixir server plus every HTTP service in packages/ and runs them in
# a single container behind one port. Each service can be switched off at run
# time with the ENABLE_* environment variables - see docker/entrypoint.sh.
#
#   docker build -t lanyard:latest .
#   docker run -p 4001:4001 -e BOT_TOKEN=<token> lanyard:latest
#
# Published images live on the GitHub Container Registry:
#
#   docker pull ghcr.io/<owner>/lanyard:latest
#
# BASE_IMAGE is the only image pulled from a registry. There is no official
# Elixir image on ghcr.io, so if your environment blocks Docker Hub entirely,
# mirror one into your own registry and pass it in:
#
#   docker build --build-arg BASE_IMAGE=ghcr.io/<owner>/elixir:1.19-alpine .
ARG BASE_IMAGE=elixir:1.19-alpine
# Bun and Caddy are fetched from their GitHub releases rather than Docker Hub
# images. Keep BUN_VERSION in step with packages/profile-readme's packageManager.
ARG BUN_VERSION=1.2.13
ARG CADDY_VERSION=2.9.1

# --- 1. the Lanyard server itself -------------------------------------------
FROM ${BASE_IMAGE} AS build-api

RUN apk add --no-cache git

ENV MIX_ENV=prod
WORKDIR /app

# get deps first so we have a cache
ADD mix.exs mix.lock /app/
RUN \
	mix local.hex --force && \
	mix local.rebar --force && \
	mix deps.get

# then make a release build
ADD config /app/config
ADD lib /app/lib
RUN \
	mix compile && \
	mix release

# --- 2. packages/graphql -----------------------------------------------------
# Reuses the base image with Alpine's Node rather than pulling node from Docker Hub.
FROM ${BASE_IMAGE} AS build-graphql

RUN apk add --no-cache nodejs npm

WORKDIR /app
COPY packages/graphql/package.json ./
RUN npm install
COPY packages/graphql/tsconfig.json ./
COPY packages/graphql/src ./src
RUN npx tsc && npm prune --omit=dev

# --- 3. packages/profile-readme ---------------------------------------------
FROM ${BASE_IMAGE} AS build-readme

ARG BUN_VERSION
ARG TARGETARCH=amd64

# Bun ships musl builds on its GitHub releases. The amd64 baseline build is used
# so the image also builds on CPUs without AVX2.
RUN apk add --no-cache curl unzip libstdc++ && \
	case "$TARGETARCH" in \
		amd64) BUN_TARGET=bun-linux-x64-musl-baseline ;; \
		arm64) BUN_TARGET=bun-linux-aarch64-musl ;; \
		*) echo "unsupported architecture: $TARGETARCH" >&2; exit 1 ;; \
	esac && \
	curl -fsSL -o /tmp/bun.zip \
		"https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${BUN_TARGET}.zip" && \
	unzip -q -j /tmp/bun.zip "${BUN_TARGET}/bun" -d /usr/local/bin && \
	chmod +x /usr/local/bin/bun && \
	rm /tmp/bun.zip && \
	bun --version

WORKDIR /app
COPY packages/profile-readme/package.json packages/profile-readme/bun.lock ./
RUN bun install --frozen-lockfile

COPY packages/profile-readme ./
# Mounted under a path prefix by the bundled reverse proxy.
ARG NEXT_BASE_PATH=/readme
ENV NEXT_BASE_PATH=$NEXT_BASE_PATH
ENV NEXT_TELEMETRY_DISABLED=1
RUN bun run build

# --- 4. caddy ----------------------------------------------------------------
# Static binary straight from the caddyserver/caddy GitHub releases.
FROM ${BASE_IMAGE} AS build-caddy

ARG CADDY_VERSION
ARG TARGETARCH=amd64

RUN apk add --no-cache curl && \
	curl -fsSL -o /tmp/caddy.tar.gz \
		"https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${TARGETARCH}.tar.gz" && \
	tar -xzf /tmp/caddy.tar.gz -C /tmp caddy && \
	chmod +x /tmp/caddy

# --- 5. runtime --------------------------------------------------------------
# Based on the Elixir image so the release's ERTS is guaranteed to match.
FROM ${BASE_IMAGE}

RUN apk add --no-cache \
	ca-certificates \
	redis \
	nodejs \
	python3 \
	py3-pip \
	supervisor \
	tini

# Caddy fronts every service on a single port.
COPY --from=build-caddy /tmp/caddy /usr/bin/caddy

# packages/mcp-server
COPY packages/mcp-server/requirements.txt /opt/lanyard-mcp/requirements.txt
RUN pip install --no-cache-dir --break-system-packages -r /opt/lanyard-mcp/requirements.txt
COPY packages/mcp-server/lanyard_server.py /opt/lanyard-mcp/lanyard_server.py

# the Elixir release
COPY --from=build-api /app/_build/prod/rel/lanyard /opt/lanyard

# packages/graphql
COPY --from=build-graphql /app/dist /opt/lanyard-graphql/dist
COPY --from=build-graphql /app/node_modules /opt/lanyard-graphql/node_modules
COPY --from=build-graphql /app/package.json /opt/lanyard-graphql/package.json

# packages/profile-readme (run with node, bun is only needed to build)
COPY --from=build-readme /app/.next /opt/lanyard-readme/.next
COPY --from=build-readme /app/node_modules /opt/lanyard-readme/node_modules
COPY --from=build-readme /app/package.json /opt/lanyard-readme/package.json
COPY --from=build-readme /app/next.config.ts /opt/lanyard-readme/next.config.ts

# packages/js-lanyard and packages/osu-nowplaying are client-side, nothing to run
COPY Caddyfile /etc/caddy/Caddyfile
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /data

# The single published port. Everything else is bound to loopback.
ENV PORT=4001 \
	API_PORT=4010 \
	GRAPHQL_PORT=8080 \
	README_PORT=3000 \
	MCP_PORT=8081 \
	ENABLE_REDIS=true \
	ENABLE_GRAPHQL=true \
	ENABLE_README=true \
	ENABLE_MCP=true \
	NEXT_TELEMETRY_DISABLED=1

EXPOSE 4001
VOLUME /data

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
