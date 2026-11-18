#!/bin/sh
# Runs on the server, in ~/paikliin.
set -e
docker compose pull
docker compose run --rm migrate
docker compose up -d app caddy
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
docker image prune -f
