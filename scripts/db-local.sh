#!/bin/sh

set -eu

db_command=${1:-}
case "$db_command" in
    migrate | reset | seed) ;;
    *)
        echo "Usage: $0 [migrate|reset|seed]" >&2
        exit 1
        ;;
esac

if [ "$db_command" = reset ]; then
    docker compose exec -T postgres psql -U app -d postgres -v ON_ERROR_STOP=1 \
        -c 'DROP DATABASE app WITH (FORCE)' -c 'CREATE DATABASE app'
fi

if [ "$db_command" != seed ]; then
    db_address=$(docker compose port postgres 5432)
    export DATABASE_URL="postgres://app:app@$db_address/app?sslmode=disable"
    atlas migrate apply --env app
fi

if [ "$db_command" = seed ] || [ "$db_command" = reset ]; then
    docker compose exec -T postgres psql -U app -d app -v ON_ERROR_STOP=1 < api/seed.sql
fi
