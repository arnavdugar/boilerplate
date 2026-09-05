-- name: ClaimIdempotencyRequest :one
INSERT INTO idempotency_requests (scope, key, request_hash, expires_at)
VALUES (@scope, @key, @request_hash, now() + interval '24 hours')
ON CONFLICT (scope, key) DO UPDATE
SET request_hash = EXCLUDED.request_hash, response_status = NULL,
    response_headers = NULL, response_body = NULL, expires_at = EXCLUDED.expires_at
WHERE idempotency_requests.expires_at <= now()
RETURNING id;

-- name: GetIdempotencyRequest :one
SELECT id, created_at, scope, key, request_hash, response_status, response_headers, response_body, expires_at
FROM idempotency_requests WHERE scope = @scope AND key = @key;

-- name: CompleteIdempotencyRequest :exec
UPDATE idempotency_requests
SET response_status = @response_status, response_headers = '{"Content-Type":["application/json"]}',
    response_body = @response_body
WHERE id = @id;
