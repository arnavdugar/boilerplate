#!/bin/sh

set -eu

# Check checksums before replaying the SQL in Atlas's disposable dev database.
atlas migrate validate --dir file://migrations
db_diff=$(atlas schema diff --env app \
    --from file://migrations --to file://api/schema.sql --format '{{ sql . }}')
if [ -n "$db_diff" ]; then
    printf '%s\n' "$db_diff" >&2
    echo "Migrations do not match api/schema.sql. Generate and review a migration." >&2
    exit 1
fi
echo "Migration history matches api/schema.sql."

db_container=$(docker run --rm --detach --publish 127.0.0.1::5432 \
    --env POSTGRES_DB=app --env POSTGRES_USER=app --env POSTGRES_PASSWORD=app \
    postgres:18-alpine)
trap 'docker rm --force "$db_container" >/dev/null' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

db_attempt=0
until docker exec "$db_container" pg_isready -h 127.0.0.1 -U app -d app >/dev/null 2>&1; do
    db_attempt=$((db_attempt + 1))
    if [ "$db_attempt" -ge 60 ]; then
        echo "Test Postgres did not become ready." >&2
        exit 1
    fi
    sleep 1
done

db_address=$(docker port "$db_container" 5432/tcp)
export DATABASE_URL="postgres://app:app@$db_address/app?sslmode=disable"
export TEST_DATABASE_URL="$DATABASE_URL"
atlas migrate apply --env app
docker exec -i "$db_container" psql -U app -d app -v ON_ERROR_STOP=1 < api/seed.sql
(cd api && go test -tags=integration -count=1 "$@" ./...)
