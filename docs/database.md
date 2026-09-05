# Database Schema

The canonical schema is [api/schema.sql](../api/schema.sql). See the README for
[migration commands](../README.md#database-migrations) and
[database checks](../README.md#database-checks).

All fields are required unless marked `(optional)`. Optional fields default to null. Required fields
have no default unless one is documented. Types use PostgreSQL notation. Relationship targets appear
in field descriptions. The indexes below are additional non-unique B-tree indexes, and their columns
are listed in index order.

## Common

All tables share the fields and relationship rules below, except where indicated.

| Field        | Type          | Description                                               |
| ------------ | ------------- | --------------------------------------------------------- |
| `id`         | `UUID`        | Primary key. Default: a database-generated UUID.          |
| `created_at` | `TIMESTAMPTZ` | Creation time. Default: the database’s current timestamp. |

### Constraints

- All relationship fields must reference an existing record when set.

## enum FileKind

The purpose of a file stored in blob storage.

## table File

A file's metadata and location in blob storage. The file bytes are stored outside the database.
Ownership and access are derived from the records that reference the file. File has no separate
owner field. An unreferenced file has no derived owner.

| Field        | Type       | Description                                                         |
| ------------ | ---------- | ------------------------------------------------------------------- |
| `kind`       | `FileKind` | File purpose.                                                       |
| `blob_store` | `TEXT`     | Configured storage backend, such as `r2_primary` or `s3mock_local`. |
| `bucket`     | `TEXT`     | Bucket within the selected blob store.                              |
| `object_key` | `TEXT`     | Object key within the bucket, including any path prefix.            |

### Constraints

- The combination of `blob_store`, `bucket`, and `object_key` must be unique.
- The combination of `id` and `kind` is unique to support foreign keys that enforce file purpose.
- `blob_store`, `bucket`, and `object_key` must be nonempty.

## table IdempotencyRequest

Storage for retryable write operations that could otherwise create duplicate records or repeat a
domain action.

| Field              | Type                  | Description                                                                                                                                 |
| ------------------ | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `scope`            | `TEXT`                | A server-defined namespace identifying the authenticated principal and operation. Derived from trusted context.                             |
| `key`              | `UUID`                | A client-generated key identifying one action.                                                                                              |
| `request_hash`     | `BYTEA`               | A 32-byte SHA-256 fingerprint of the HTTP method, request target including resource identifiers and relevant query parameters, and payload. |
| `response_status`  | `SMALLINT` (optional) | HTTP response status saved for replay.                                                                                                      |
| `response_headers` | `JSONB` (optional)    | Response headers saved for replay.                                                                                                          |
| `response_body`    | `BYTEA` (optional)    | The exact response body saved for replay. A completed response without a body uses an empty byte string rather than null.                   |
| `expires_at`       | `TIMESTAMPTZ`         | Retention deadline.                                                                                                                         |

### Constraints

- The combination of `scope` and `key` must be unique.
- `scope` must contain 1–255 characters.
- `request_hash` must contain exactly 32 bytes.
- When set, `response_status` must be between 200 and 599, and `response_headers` must be a JSON
  object.
- `response_status`, `response_headers`, and `response_body` must either all be null while handling
  the request or all be set for replay.
- `expires_at` must be later than `created_at`.

### Query Indexes

- `(expires_at)` supports finding expired records for cleanup. Expiry does not automatically delete
  rows or release their unique keys.

## table User

Storage for application users. Uses only the common `id` and `created_at` fields, with no additional
fields, constraints, or query indexes.
