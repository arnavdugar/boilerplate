# Idempotent writes

Use `Write` for retryable JSON writes. It owns one transaction for the idempotency claim, mutations,
and encoded response. Perform all persistence work through the callback's `*database.Queries`;
external side effects are outside this transaction.

Choose a scope containing the operation, caller, and relevant resource identifiers. Authenticate and
authorize access before calling `Write`, including on retries. Pass the client-provided UUID key and
all input that affects the operation. `Write` hashes the JSON encoding of that input.

Successful responses replay for 24 hours. Concurrent requests with the same scope and key wait for
the claim's transaction. Different input returns `ErrConflict`, which handlers map to HTTP 409.
Expired claims can be reused. Failed mutations, encoding, or response persistence roll back the
claim and all transaction writes so a retry can run again.

Supply one fixed success status per operation. `Write` returns the saved JSON body; the handler
supplies that status and `application/json`. Arbitrary response headers and varying success statuses
are not supported. Unexpected failures return errors for shared HTTP error handling.

The shared `IdempotencyKey` parameter in [the contract](../../../schema/openapi.yaml) is available
for write endpoints. Expiry permits reuse but does not delete old rows; applications own any
retention cleanup.

Run integration tests through `./scripts/test-db.sh -race` from the repository root. They require
`TEST_DATABASE_URL` and cover concurrent replay, scope isolation, conflicting input, rollback, and
expired keys.
