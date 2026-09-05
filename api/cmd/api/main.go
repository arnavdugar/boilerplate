package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/getsentry/sentry-go"
	"github.com/jackc/pgx/v5/pgxpool"

	"api/database"
	"api/server"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx); err != nil {
		slog.ErrorContext(ctx, "api failed", "error", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) (runErr error) {
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		return errors.New("ENVIRONMENT is required")
	}
	var sentryClient *sentry.Client
	// Local development must not send events or traces to Sentry.
	if environment != "local" {
		dsn := os.Getenv("SENTRY_DSN")
		if dsn == "" {
			return errors.New("configure Sentry: SENTRY_DSN is required outside local")
		}
		var err error
		sentryClient, err = sentry.NewClient(sentry.ClientOptions{
			// Request metadata can contain credentials and other sensitive values.
			DataCollection: &sentry.DataCollection{
				Cookies:    &sentry.KeyValueCollectionBehavior{Mode: sentry.CollectionOff},
				HTTPBodies: []sentry.BodyType{},
				HTTPHeaders: &sentry.HeaderCollectionConfig{
					Request:  &sentry.KeyValueCollectionBehavior{Mode: sentry.CollectionOff},
					Response: &sentry.KeyValueCollectionBehavior{Mode: sentry.CollectionOff},
				},
				QueryParams: &sentry.KeyValueCollectionBehavior{Mode: sentry.CollectionOff},
				UserInfo:    sentry.Set(false),
			},
			Dsn:           dsn,
			EnableTracing: true,
			Environment:   environment,
			HTTPClient: &http.Client{
				CheckRedirect: func(*http.Request, []*http.Request) error {
					return http.ErrUseLastResponse
				},
				Timeout: time.Second,
			},
			Tags:             map[string]string{"service": "api"},
			TracesSampleRate: 0.1,
			// Cloud Run can suspend CPU after a response, so deliver errors before returning.
			Transport: sentry.NewHTTPSyncTransport(),
		})
		if err != nil {
			return fmt.Errorf("configure Sentry: %w", err)
		}
		defer func() {
			if runErr != nil {
				sentryClient.CaptureException(runErr, nil, nil)
			}
			sentryClient.Flush(time.Second)
			sentryClient.Close()
		}()
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	startupCtx, cancelStartup := context.WithTimeout(ctx, 5*time.Second)
	defer cancelStartup()
	pool, err := pgxpool.New(startupCtx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer pool.Close()
	if err := pool.Ping(startupCtx); err != nil {
		return fmt.Errorf("ping database: %w", err)
	}
	s3Bucket := os.Getenv("S3_BUCKET")
	if s3Bucket == "" {
		return errors.New("S3_BUCKET is required")
	}
	awsConfig, err := config.LoadDefaultConfig(startupCtx)
	if err != nil {
		return fmt.Errorf("load S3 configuration: %w", err)
	}
	s3Client := s3.NewFromConfig(awsConfig, func(options *s3.Options) {
		options.UsePathStyle = true
	})
	if _, err := s3Client.HeadBucket(startupCtx, &s3.HeadBucketInput{Bucket: &s3Bucket}); err != nil {
		return fmt.Errorf("connect to S3 bucket %q: %w", s3Bucket, err)
	}
	cancelStartup()

	queries := database.New(pool)
	handler, err := server.NewHandler(pool, queries, s3Client, s3Bucket, sentryClient)
	if err != nil {
		return fmt.Errorf("create API handler: %w", err)
	}

	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           handler,
		IdleTimeout:       60 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      10 * time.Second,
	}
	listener, err := net.Listen("tcp", httpServer.Addr)
	if err != nil {
		return fmt.Errorf("listen for api: %w", err)
	}
	defer listener.Close()
	defer httpServer.Close()
	slog.InfoContext(ctx, "listening",
		"address", listener.Addr().String(), "environment", environment)
	serveErr := make(chan error, 1)
	go func() {
		err := httpServer.Serve(listener)
		if errors.Is(err, http.ErrServerClosed) {
			err = nil
		}
		if err != nil {
			err = fmt.Errorf("serve api: %w", err)
		}
		serveErr <- err
	}()

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
	}

	// The signal context is already canceled; draining needs its own deadline.
	// Leave time for database cleanup before Cloud Run's 10-second SIGKILL.
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancelShutdown()
	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		return errors.Join(fmt.Errorf("shutdown api: %w", err), httpServer.Close())
	}
	return <-serveErr
}
