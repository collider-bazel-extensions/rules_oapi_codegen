//go:build tools

// Package internal keeps oapi-codegen/runtime in go.mod for `go mod tidy`;
// the generated client imports it, but that code exists only in bazel-out.
package internal

import _ "github.com/oapi-codegen/runtime/types"
