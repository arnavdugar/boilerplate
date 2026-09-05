package health

import (
	"context"
	"net/http"
	"time"
)

//go:generate go tool mockgen -source=health.go -destination=health_mock_test.go -package=health

// DatabasePinger is the database dependency required by readiness checks.
type DatabasePinger interface {
	Ping(context.Context) error
}

// HealthHandler implements the health and readiness endpoints.
type HealthHandler struct {
	database DatabasePinger
}

func NewHandler(database DatabasePinger) *HealthHandler {
	return &HealthHandler{database: database}
}

func (*HealthHandler) GetHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
}

func (h *HealthHandler) GetReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), time.Second)
	defer cancel()
	code := http.StatusOK
	if h.database.Ping(ctx) != nil {
		code = http.StatusServiceUnavailable
	}
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
}
