package api

//go:generate go run github.com/ogen-go/ogen/cmd/ogen@v1.24.0 --clean --config ogen.yaml --target openapi --package openapi ../schema/openapi.yaml
//go:generate go run github.com/sqlc-dev/sqlc/cmd/sqlc@v1.31.1 generate
