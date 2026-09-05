package debug

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestProfilingRoutes(t *testing.T) {
	for _, test := range []struct {
		contentType string
		method      string
		name        string
		path        string
		status      int
	}{{
		contentType: "text/html; charset=utf-8",
		method:      http.MethodGet,
		name:        "profile index",
		path:        "/debug/pprof/",
		status:      http.StatusOK,
	}, {
		contentType: "application/octet-stream",
		method:      http.MethodGet,
		name:        "heap profile",
		path:        "/debug/pprof/heap",
		status:      http.StatusOK,
	}, {
		contentType: "text/plain; charset=utf-8",
		method:      http.MethodPost,
		name:        "profiles reject writes",
		path:        "/debug/pprof/heap",
		status:      http.StatusMethodNotAllowed,
	}} {
		t.Run(test.name, func(t *testing.T) {
			handler := NewHandler()
			response := httptest.NewRecorder()

			handler.ServeHTTP(response, httptest.NewRequest(test.method, test.path, nil))

			assert.Equal(t, test.status, response.Code)
			assert.Equal(t, test.contentType, response.Header().Get("Content-Type"))
			assert.NotEmpty(t, response.Body.Bytes())
		})
	}
}
