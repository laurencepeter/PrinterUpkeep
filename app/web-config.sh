#!/bin/sh
# Generate runtime config for the Flutter web app from the container's env vars.
# nginx:alpine runs every /docker-entrypoint.d/*.sh before starting nginx, so
# this writes /config.json (read by the app at startup) on each boot — letting
# one pre-built image be pointed at any Supabase instance via env, no rebuild.
set -e
cat > /usr/share/nginx/html/config.json <<EOF
{"SUPABASE_URL":"${SUPABASE_URL:-}","SUPABASE_ANON_KEY":"${SUPABASE_ANON_KEY:-}"}
EOF
echo "web-config: wrote /config.json (SUPABASE_URL=${SUPABASE_URL:-<empty>})"
