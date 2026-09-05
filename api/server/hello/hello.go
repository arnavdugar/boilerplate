// Package hello implements the temporary scaffold example API.
package hello

import (
	"context"

	"api/openapi"
)

type HelloHandler struct{}

func NewHandler() *HelloHandler { return &HelloHandler{} }

func (*HelloHandler) GetHello(context.Context) (*openapi.Hello, error) {
	return &openapi.Hello{Content: "Hello world!"}, nil
}
