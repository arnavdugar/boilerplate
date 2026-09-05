package health

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestGetReady(t *testing.T) {
	for _, test := range []struct {
		code int
		err  error
		name string
	}{{
		code: http.StatusOK,
		name: "ready",
	}, {
		code: http.StatusServiceUnavailable,
		err:  errors.New("private database connection details"),
		name: "database unavailable",
	}} {
		t.Run(test.name, func(t *testing.T) {
			database := NewMockDatabasePinger(gomock.NewController(t))
			database.EXPECT().Ping(gomock.Any()).DoAndReturn(func(ctx context.Context) error {
				deadline, ok := ctx.Deadline()
				require.True(t, ok, "database ping must have a deadline")
				remaining := time.Until(deadline)
				assert.Positive(t, remaining)
				assert.LessOrEqual(t, remaining, time.Second)
				return test.err
			})
			response := httptest.NewRecorder()
			NewHandler(database).GetReady(response, httptest.NewRequest(http.MethodGet, "/ready", nil))
			assert.Equal(t, test.code, response.Code)
			assert.Empty(t, response.Body.String())
			assert.Empty(t, response.Header().Get("Content-Type"))
			assert.Equal(t, "no-store", response.Header().Get("Cache-Control"))
		})
	}
}

func TestGetReadyPropagatesCancellation(t *testing.T) {
	database := NewMockDatabasePinger(gomock.NewController(t))
	database.EXPECT().Ping(gomock.Any()).DoAndReturn(func(ctx context.Context) error {
		assert.ErrorIs(t, ctx.Err(), context.Canceled)
		return ctx.Err()
	})
	ctx, cancel := context.WithCancel(t.Context())
	cancel()

	response := httptest.NewRecorder()
	NewHandler(database).GetReady(response, httptest.NewRequest(http.MethodGet, "/ready", nil).WithContext(ctx))
	assert.Equal(t, http.StatusServiceUnavailable, response.Code)
	assert.Empty(t, response.Body.String())
}

func TestGetHealthDoesNotAccessDatabase(t *testing.T) {
	// With no expectations, gomock fails the test if the handler calls Ping.
	database := NewMockDatabasePinger(gomock.NewController(t))
	response := httptest.NewRecorder()
	NewHandler(database).GetHealth(response, httptest.NewRequest(http.MethodGet, "/health", nil))
	assert.Equal(t, http.StatusOK, response.Code)
	assert.Empty(t, response.Body.String())
	assert.Empty(t, response.Header().Get("Content-Type"))
	assert.Equal(t, "no-store", response.Header().Get("Cache-Control"))
}
