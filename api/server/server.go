package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"api/database"
	"api/openapi"
	"api/server/health"
	"api/server/hello"
	"api/server/httperror"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/getsentry/sentry-go"
	sentryhttp "github.com/getsentry/sentry-go/http"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/ogen-go/ogen/ogenerrors"
)

// NewHandler assembles probes and API routes. Shared error handling takes
// precedence over any supplied ogen server options.
func NewHandler(
	pool *pgxpool.Pool, queries *database.Queries, s3Client *s3.Client, s3Bucket string,
	sentryClient *sentry.Client, serverOptions ...openapi.ServerOption,
) (http.Handler, error) {
	mux := http.NewServeMux()
	probes := health.NewHandler(pool)
	mux.HandleFunc("GET /health", probes.GetHealth)
	mux.HandleFunc("GET /ready", probes.GetReady)
	generated, err := openapi.NewServer(
		&handler{HelloHandler: hello.NewHandler()},
		append(serverOptions, openapi.WithErrorHandler(handleAPIError))...)
	if err != nil {
		return nil, err
	}
	mux.Handle("/api/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Body != nil {
			r.Body = http.MaxBytesReader(w, r.Body, 16<<10)
		}
		generated.ServeHTTP(w, r)
	}))
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mux.ServeHTTP(&responseWriter{ResponseWriter: w}, r)
	})
	if sentryClient == nil {
		return handler, nil
	}

	// Give each request its own scope and report panics before repanicking.
	sentryHandler := sentryhttp.New(sentryhttp.Options{Repanic: true}).Handle(handler)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hub := sentry.NewHub(sentryClient, sentry.NewScope())
		sentryHandler.ServeHTTP(w, r.WithContext(sentry.SetHubOnContext(r.Context(), hub)))
	}), nil
}

type handler struct {
	*hello.HelloHandler
}

var _ openapi.Handler = (*handler)(nil)

func handleAPIError(_ context.Context, w http.ResponseWriter, r *http.Request, err error) {
	// Preserve ogen's status codes without exposing error details.
	code := ogenerrors.ErrorCode(err)
	if code != http.StatusInternalServerError {
		w.WriteHeader(code)
		return
	}
	slog.ErrorContext(r.Context(), "handle request", "error", err, "method", r.Method, "route", r.Pattern)
	if hub := sentry.GetHubFromContext(r.Context()); hub != nil {
		hub.CaptureException(err)
	}
	// A response write can fail after headers or part of the body are sent.
	// Report it without appending a second response.
	// Ogen and HTTP middleware can wrap the response tracker.
	for writer := w; writer != nil; {
		if tracked, ok := writer.(*responseWriter); ok && tracked.written {
			return
		}
		wrapper, ok := writer.(interface{ Unwrap() http.ResponseWriter })
		if !ok {
			break
		}
		writer = wrapper.Unwrap()
	}
	var responseErr *httperror.Error
	if errors.As(err, &responseErr) {
		responseErr.WriteResponse(w)
		return
	}
	http.Error(w, http.StatusText(http.StatusInternalServerError), http.StatusInternalServerError)
}

type responseWriter struct {
	http.ResponseWriter
	written bool
}

func (w *responseWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

func (w *responseWriter) WriteHeader(status int) {
	if status >= 200 || status == http.StatusSwitchingProtocols {
		w.written = true
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *responseWriter) Write(body []byte) (int, error) {
	w.written = true
	return w.ResponseWriter.Write(body)
}
