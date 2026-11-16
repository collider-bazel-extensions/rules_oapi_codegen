"""Public API for rules_oapi_codegen."""

load("//private:go_oapi_client.bzl", _go_oapi_client = "go_oapi_client")
load("//private:oapi_codegen.bzl", _oapi_codegen = "oapi_codegen")
load("//private:ts_oapi_types.bzl", _ts_oapi_types = "ts_oapi_types")

oapi_codegen = _oapi_codegen
go_oapi_client = _go_oapi_client
ts_oapi_types = _ts_oapi_types
