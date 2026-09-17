#!/bin/sh
# Generates a supervisord config from the ENABLE_* environment variables and
# hands over to supervisord, which runs every enabled service in this container.
set -e

CONF=/tmp/supervisord.conf

if [ -z "$BOT_TOKEN" ]; then
	echo "BOT_TOKEN is not set - the Discord bot and gateway will not start." >&2
	echo "Create a bot at https://discord.com/developers/applications and pass" >&2
	echo "its token with -e BOT_TOKEN=<token>." >&2
	exit 1
fi

# When no external Redis is configured, use the one bundled in this image.
if [ -z "$REDIS_URL" ] && [ -z "$REDIS_DSN" ] && [ -z "$REDIS_URI" ]; then
	if [ "$ENABLE_REDIS" = "true" ]; then
		REDIS_URL="redis://127.0.0.1:6379"
		export REDIS_URL
	fi
else
	# An external Redis was given, so don't run our own.
	ENABLE_REDIS=false
fi

# Caddy owns the published port; the Elixir release reads PORT, so hand the
# published one to Caddy under its own name before reassigning PORT below.
export LISTEN_PORT="$PORT"

# Everything but Caddy listens on loopback only.
export LANYARD_API_URL="http://127.0.0.1:${API_PORT}"
export MCP_HOST=127.0.0.1
export MCP_TRANSPORT="${MCP_TRANSPORT:-streamable-http}"

cat > "$CONF" <<CONFEOF
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid

[program:caddy]
command=/usr/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
autorestart=true
priority=50
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true

[program:api]
command=/opt/lanyard/bin/lanyard start
autorestart=true
priority=20
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
CONFEOF

if [ "$ENABLE_REDIS" = "true" ]; then
	cat >> "$CONF" <<CONFEOF

[program:redis]
command=redis-server --dir /data --save 60 1
autorestart=true
priority=10
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
CONFEOF
fi

if [ "$ENABLE_GRAPHQL" = "true" ]; then
	cat >> "$CONF" <<CONFEOF

[program:graphql]
command=node /opt/lanyard-graphql/dist/main.js
directory=/opt/lanyard-graphql
autorestart=true
priority=30
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
CONFEOF
fi

if [ "$ENABLE_README" = "true" ]; then
	cat >> "$CONF" <<CONFEOF

[program:profile-readme]
command=node /opt/lanyard-readme/node_modules/next/dist/bin/next start -H 127.0.0.1 -p ${README_PORT}
directory=/opt/lanyard-readme
autorestart=true
priority=30
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
CONFEOF
fi

if [ "$ENABLE_MCP" = "true" ]; then
	cat >> "$CONF" <<CONFEOF

[program:mcp]
command=python3 /opt/lanyard-mcp/lanyard_server.py
directory=/opt/lanyard-mcp
autorestart=true
priority=30
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
redirect_stderr=true
CONFEOF
fi

# The Elixir release and Next both read PORT; the release gets the internal one
# (Next is given -p explicitly above).
export PORT="$API_PORT"

exec supervisord -c "$CONF"
