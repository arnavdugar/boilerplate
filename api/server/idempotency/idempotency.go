package idempotency

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"

	"api/database"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrConflict = errors.New("idempotency key was already used with different input")

// Write owns the claim, domain writes, history, and replay response in one transaction.
func Write[T any](
	ctx context.Context, pool *pgxpool.Pool, queries *database.Queries, scope string, key pgtype.UUID,
	input any, status int16, mutate func(*database.Queries) (T, error), encode func(T) ([]byte, error),
) ([]byte, error) {
	payload, err := json.Marshal(input)
	if err != nil {
		return nil, err
	}
	hash := sha256.Sum256(payload)
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	q := queries.WithTx(tx)
	claim, err := q.ClaimIdempotencyRequest(
		ctx, database.ClaimIdempotencyRequestParams{
			Key:         key,
			RequestHash: hash[:],
			Scope:       scope,
		})
	if errors.Is(err, pgx.ErrNoRows) {
		saved, err := q.GetIdempotencyRequest(
			ctx, database.GetIdempotencyRequestParams{
				Key:   key,
				Scope: scope,
			})
		if err != nil {
			return nil, err
		}
		if !bytes.Equal(saved.RequestHash, hash[:]) {
			return nil, ErrConflict
		}
		if saved.ResponseStatus == nil || *saved.ResponseStatus != status || saved.ResponseBody == nil {
			return nil, fmt.Errorf("incomplete idempotency response: %s", saved.ID.String())
		}
		return saved.ResponseBody, nil
	}
	if err != nil {
		return nil, err
	}
	row, err := mutate(q)
	if err != nil {
		return nil, err
	}
	body, err := encode(row)
	if err != nil {
		return nil, err
	}
	if err := q.CompleteIdempotencyRequest(
		ctx, database.CompleteIdempotencyRequestParams{
			ID:             claim,
			ResponseBody:   body,
			ResponseStatus: &status,
		}); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return body, nil
}
