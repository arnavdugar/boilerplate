-- Create the empty enum before files; later migrations add domain-specific kinds.
CREATE TYPE "file_kind" AS ENUM ();
-- Create "files" table
CREATE TABLE "files" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "kind" file_kind NOT NULL,
  "blob_store" text NOT NULL,
  "bucket" text NOT NULL,
  "object_key" text NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "files_blob_location_key" UNIQUE ("blob_store", "bucket", "object_key"),
  CONSTRAINT "files_id_kind_key" UNIQUE ("id", "kind"),
  CONSTRAINT "files_blob_store_check" CHECK (blob_store <> ''::text),
  CONSTRAINT "files_bucket_check" CHECK (bucket <> ''::text),
  CONSTRAINT "files_object_key_check" CHECK (object_key <> ''::text)
);
-- Create "idempotency_requests" table
CREATE TABLE "idempotency_requests" (
  "id" uuid NOT NULL DEFAULT uuidv7(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "scope" text NOT NULL,
  "key" uuid NOT NULL,
  "request_hash" bytea NOT NULL,
  "response_status" smallint NULL,
  "response_headers" jsonb NULL,
  "response_body" bytea NULL,
  "expires_at" timestamptz NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "idempotency_requests_scope_key" UNIQUE ("scope", "key"),
  CONSTRAINT "idempotency_requests_expiry" CHECK (expires_at > created_at),
  CONSTRAINT "idempotency_requests_request_hash_check" CHECK (octet_length(request_hash) = 32),
  CONSTRAINT "idempotency_requests_response_complete" CHECK (((response_status IS NULL) AND (response_headers IS NULL) AND (response_body IS NULL)) OR ((response_status IS NOT NULL) AND (response_headers IS NOT NULL) AND (response_body IS NOT NULL))),
  CONSTRAINT "idempotency_requests_response_headers_check" CHECK (jsonb_typeof(response_headers) = 'object'::text),
  CONSTRAINT "idempotency_requests_response_status_check" CHECK ((response_status >= 200) AND (response_status <= 599)),
  CONSTRAINT "idempotency_requests_scope_check" CHECK ((length(scope) >= 1) AND (length(scope) <= 255))
);
-- Create index "idempotency_requests_expires_at_idx" to table: "idempotency_requests"
CREATE INDEX "idempotency_requests_expires_at_idx" ON "idempotency_requests" ("expires_at");
-- Create "users" table
CREATE TABLE "users" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);
