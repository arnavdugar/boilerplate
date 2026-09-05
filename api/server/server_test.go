package server

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"api/openapi"
	"api/server/httperror"

	"github.com/getsentry/sentry-go"
	"github.com/ogen-go/ogen/middleware"
	"github.com/ogen-go/ogen/ogenerrors"
	"github.com/ogen-go/ogen/validate"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHelloAPI(t *testing.T) {
	handler, err := NewHandler(nil, nil, nil, "", nil)
	require.NoError(t, err)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil))

	assert.Equal(t, http.StatusOK, response.Code)
	assert.Equal(t, "application/json; charset=utf-8", response.Header().Get("Content-Type"))
	assert.JSONEq(t, `{"content":"Hello world!"}`, response.Body.String())
}

func TestProbeRouting(t *testing.T) {
	for _, test := range []struct {
		method string
		name   string
		path   string
		status int
	}{{
		method: http.MethodGet,
		name:   "liveness is public",
		path:   "/health",
		status: http.StatusOK,
	}, {
		method: http.MethodPost,
		name:   "readiness rejects writes",
		path:   "/ready",
		status: http.StatusMethodNotAllowed,
	}, {
		method: http.MethodGet,
		name:   "profiling is absent from the public handler",
		path:   "/debug/pprof/",
		status: http.StatusNotFound,
	}} {
		t.Run(test.name, func(t *testing.T) {
			handler, err := NewHandler(nil, nil, nil, "", nil)
			require.NoError(t, err)
			response := httptest.NewRecorder()

			handler.ServeHTTP(response, httptest.NewRequest(test.method, test.path, nil))

			assert.Equal(t, test.status, response.Code)
		})
	}
}

func TestHandlerPreservesOgenErrorStatusWithoutReportingDetails(t *testing.T) {
	client, transport := testClient(t)
	handler, err := NewHandler(nil, nil, nil, "", client, openapi.WithMiddleware(func(middleware.Request, middleware.Next) (middleware.Response, error) {
		return middleware.Response{}, &ogenerrors.DecodeRequestError{Err: validate.InvalidContentType("private content type")}
	}))
	require.NoError(t, err)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil))

	assert.Equal(t, http.StatusUnsupportedMediaType, response.Code)
	assert.Empty(t, response.Body.String())
	assert.Empty(t, transport.events)
}

func TestHandlerReportsFailuresWithSafeResponses(t *testing.T) {
	cause := errors.New("private upstream details")
	for _, test := range []struct {
		body    string
		err     error
		headers http.Header
		name    string
		status  int
	}{{
		body:   "Internal Server Error\n",
		err:    cause,
		name:   "unexpected failure",
		status: http.StatusInternalServerError,
	}, {
		body: "upstream service unavailable\n",
		err: fmt.Errorf("call upstream: %w", &httperror.Error{
			Cause:      cause,
			Headers:    http.Header{"Cache-Control": {"no-store"}},
			Message:    "upstream service unavailable",
			StatusCode: http.StatusBadGateway,
		}),
		headers: http.Header{"Cache-Control": {"no-store"}},
		name:    "failure with a public response",
		status:  http.StatusBadGateway,
	}} {
		t.Run(test.name, func(t *testing.T) {
			client, transport := testClient(t)
			handler, err := NewHandler(nil, nil, nil, "", client, openapi.WithMiddleware(func(middleware.Request, middleware.Next) (middleware.Response, error) {
				return middleware.Response{}, test.err
			}))
			require.NoError(t, err)
			response := httptest.NewRecorder()

			handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil))

			assert.Equal(t, test.status, response.Code)
			assert.Equal(t, test.body, response.Body.String())
			for name, values := range test.headers {
				assert.Equal(t, values, response.Header().Values(name))
			}
			require.Len(t, transport.events, 1)
			require.NotEmpty(t, transport.events[0].Exception)
			assert.Equal(t, cause.Error(), transport.events[0].Exception[0].Value)
		})
	}
}

func TestHandlerReportsWriteFailureWithoutAppendingResponse(t *testing.T) {
	client, transport := testClient(t)
	handler, err := NewHandler(nil, nil, nil, "", client)
	require.NoError(t, err)
	writer := &failingResponseWriter{
		ResponseRecorder: httptest.NewRecorder(),
		err:              errors.New("private write failure"),
	}

	handler.ServeHTTP(writer, httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil))

	assert.Equal(t, http.StatusOK, writer.Code)
	assert.Equal(t, "partial response", writer.Body.String())
	assert.Equal(t, 1, writer.writes)
	assert.Len(t, transport.events, 1)
}

func TestHandlerReportsPanicsBeforeRepanicking(t *testing.T) {
	client, transport := testClient(t)
	handler, err := NewHandler(nil, nil, nil, "", client, openapi.WithMiddleware(func(middleware.Request, middleware.Next) (middleware.Response, error) {
		panic(errors.New("test panic"))
	}))
	require.NoError(t, err)
	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil)

	assert.PanicsWithError(t, "test panic", func() { handler.ServeHTTP(response, request) })

	require.Len(t, transport.events, 1)
	require.NotEmpty(t, transport.events[0].Exception)
	assert.Equal(t, "test panic", transport.events[0].Exception[0].Value)
}

func TestHandlerContinuesBrowserTrace(t *testing.T) {
	client, transport := testClient(t)
	handler, err := NewHandler(nil, nil, nil, "", client)
	require.NoError(t, err)
	request := httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil)
	request.Header.Set(sentry.SentryTraceHeader, "0123456789abcdef0123456789abcdef-0123456789abcdef-1")
	request.Header.Set(sentry.SentryBaggageHeader, "sentry-public_key=public,sentry-trace_id=0123456789abcdef0123456789abcdef")

	handler.ServeHTTP(httptest.NewRecorder(), request)

	require.Len(t, transport.events, 1)
	event := transport.events[0]
	assert.Equal(t, "0123456789abcdef0123456789abcdef", fmt.Sprint(event.Contexts["trace"]["trace_id"]))
	assert.Equal(t, "0123456789abcdef", fmt.Sprint(event.Contexts["trace"]["parent_span_id"]))
}

type failingResponseWriter struct {
	*httptest.ResponseRecorder
	err    error
	writes int
}

func (w *failingResponseWriter) Write([]byte) (int, error) {
	w.writes++
	n, _ := w.ResponseRecorder.Write([]byte("partial response"))
	return n, w.err
}

type eventTransport struct{ events []*sentry.Event }

func (*eventTransport) Close()                                {}
func (*eventTransport) Configure(sentry.ClientOptions)        {}
func (*eventTransport) Flush(time.Duration) bool              { return true }
func (*eventTransport) FlushWithContext(context.Context) bool { return true }
func (t *eventTransport) SendEvent(event *sentry.Event)       { t.events = append(t.events, event) }

func testClient(t *testing.T) (*sentry.Client, *eventTransport) {
	t.Helper()
	transport := &eventTransport{}
	client, err := sentry.NewClient(sentry.ClientOptions{
		Dsn:           "https://public@example.com/1",
		EnableTracing: true,
		Transport:     transport,
	})
	require.NoError(t, err)
	t.Cleanup(client.Close)
	return client, transport
}
