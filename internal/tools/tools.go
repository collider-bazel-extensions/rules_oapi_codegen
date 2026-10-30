//go:build tools

// Package tools pins the Go modules rules_oapi_codegen builds or links
// against (including what tests/server's generated server imports), so
// `go mod tidy` keeps them in go.mod. Nothing imports it.
package tools

import (
	_ "github.com/getkin/kin-openapi/openapi3"
	_ "github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen"
	_ "github.com/oapi-codegen/runtime"
	_ "github.com/oapi-codegen/runtime/strictmiddleware/nethttp"
	_ "github.com/oapi-codegen/runtime/types"
)
