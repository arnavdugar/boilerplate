CREATE TYPE file_kind AS ENUM ();

CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    kind file_kind NOT NULL,
    blob_store TEXT NOT NULL CHECK (blob_store <> ''),
    bucket TEXT NOT NULL CHECK (bucket <> ''),
    object_key TEXT NOT NULL CHECK (object_key <> ''),
    CONSTRAINT files_blob_location_key UNIQUE (blob_store, bucket, object_key),
    CONSTRAINT files_id_kind_key UNIQUE (id, kind)
);

CREATE TABLE idempotency_requests (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    scope TEXT NOT NULL CHECK (length(scope) BETWEEN 1 AND 255),
    key UUID NOT NULL,
    request_hash BYTEA NOT NULL CHECK (octet_length(request_hash) = 32),
    response_status SMALLINT CHECK (response_status BETWEEN 200 AND 599),
    response_headers JSONB CHECK (jsonb_typeof(response_headers) = 'object'),
    response_body BYTEA,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT idempotency_requests_scope_key UNIQUE (scope, key),
    CONSTRAINT idempotency_requests_response_complete CHECK (
        (response_status IS NULL AND response_headers IS NULL AND response_body IS NULL)
        OR
        (response_status IS NOT NULL AND response_headers IS NOT NULL AND response_body IS NOT NULL)
    ),
    CONSTRAINT idempotency_requests_expiry CHECK (expires_at > created_at)
);

CREATE INDEX idempotency_requests_expires_at_idx ON idempotency_requests (expires_at);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
