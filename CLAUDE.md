# rules_oapi_codegen

Bazel rules that run [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen)
(OpenAPI 3 → Go) hermetically. oapi-codegen is built from source with
rules_go; the codegen action uses the rules_go SDK's `go`, so no host Go is
needed.

## Commit requirements

- All tests must pass before any commit with code changes:
  `bazel test //...` **and** `cd e2e/consumer && bazel test //...`.
- All documentation (`README.md`, `DESIGN.md`, `CLAUDE.md`) must be updated to
  reflect any code changes before committing. This includes new rules, changed
  attributes, new public API surface, and behaviour changes.

## Repo layout

```
rules_oapi_codegen/
├── MODULE.bazel              # Bzlmod module: rules_go, gazelle, go_sdk, go_deps
├── go.mod / go.sum           # Pins oapi-codegen + runtime (read by go_deps)
├── WORKSPACE                 # Stub (Bzlmod-only)
├── defs.bzl                  # Public API re-exports
├── repositories.bzl          # Stub (Bzlmod-only)
├── BUILD.bazel               # //:oapi-codegen alias to the from-source go_binary
├── DESIGN.md                 # Design decisions
├── internal/tools/tools.go   # `//go:build tools` imports so `go mod tidy` keeps deps
├── private/
│   ├── oapi_codegen.bzl      # oapi_codegen rule (run_shell with the SDK's go on PATH)
│   ├── versions.bzl          # OAPI_CODEGEN_VERSION (must equal go.mod; header rewrite)
│   └── go_oapi_client.bzl    # go_oapi_client macro (oapi_codegen + go_library)
├── tools/
│   └── update_versions.sh    # Bump oapi-codegen / runtime in go.mod + go mod tidy
├── tests/
│   ├── analysis_tests.bzl    # Output naming, argv per attribute, validation
│   ├── assert_generated.sh   # Generated-file header check
│   ├── version_sync_test.sh  # versions.bzl == go.mod
│   ├── petstore/             # go_oapi_client + client vs httptest server
│   ├── config/               # config files, spec split across files ($ref + data)
│   └── server/               # generated strict net/http server + petstore client
└── e2e/consumer/             # Separate root module (own Go SDK, own go_deps); in .bazelignore
```

## Key concepts

### Why a custom rule

oapi-codegen formats output through `golang.org/x/tools/imports`, which runs
`go env`. `oapi_codegen` resolves `@rules_go//go:toolchain` and runs:

```
GOROOT=<sdk> PATH=<sdk>/bin:$PATH GOTOOLCHAIN=local GOPROXY=off GOENV=off GOWORK=off \
  oapi-codegen [-config c] [-package p] [-generate a,b] -o <out> <spec>
```

then fails if `<out>` is missing (a config's `output:` beats `-o`), and
rewrites the header's "unknown module path version unknown version" (no Go
build info under rules_go < 0.60) to the pinned module/version from
`private/versions.bzl`.

### Flag precedence

- No config: `package` required (analysis error otherwise), `generate`
  defaults to `types,client`.
- With config: `package` / `generate` override the config only when set.

### Go module graph

`go_deps.from_file(go_mod = "//:go.mod")`. Consumers' `go.mod` files merge with
ours by MVS. **`bazel_dep` versions are minimums imposed on consumers**: keep
rules_go / gazelle at the lowest versions that work. rules_go 0.65.0 pulled
`golang.org/x/mod` v0.41.0 (Go ≥ 1.26) into consumers' graphs and broke Go 1.25
consumers; see DESIGN.md #13.

### Generating go.mod / go.sum without host Go

```sh
bazel run @rules_go//go -- mod tidy -e   # -e: tests import generated packages
```

A new module needs an empty `go.sum` first (`go_deps` reads it before `go`
can run).

## Public API

```python
load("@rules_oapi_codegen//:defs.bzl", "go_oapi_client", "oapi_codegen")

go_oapi_client(
    name = "api",                      # go_library; codegen target is api_gen
    spec = "openapi.yaml",
    importpath = "example.com/x/api",
    package = None,                    # default: last importpath element
    generate = ["types", "client"],
    config = None,
    data = [],                         # $ref targets
    deps = [],                         # added to runtime + runtime/types
)

oapi_codegen(
    name = "gen",
    spec = "openapi.yaml",
    package = "api",                   # required unless config sets package:
    generate = [],                     # [] → types,client (no config) / config's choice
    config = None,                     # must not set output:
    data = [],
    out = "",                          # default <name>.gen.go
)
```

## Development

```sh
bazel test //...                          # analysis + end-to-end
(cd e2e/consumer && bazel test //...)     # consumer module, Go 1.25 SDK
```

Neither needs Docker or a host Go. CI runs both on Bazel 8.x and 9.x after
removing host Go: PATH entries holding `go` are dropped, and `go`/`gofmt` are
deleted from `/bin`, `/usr/bin` and `/usr/local/bin` (Bazel's default action
PATH).

### Test results (last full run: 2026-10-30, Bazel 9.3.1, no host Go)

| Test target | What it verifies |
|---|---|
| `//tests:oapi_codegen_analysis` | output naming, `-package`/`-generate`/`-config` argv, nopkg failure |
| `//tests:go_oapi_client_analysis` | `<name>_gen` → `<name>.gen.go`, package from importpath |
| `//tests:petstore_generated_test` | generated header (DO NOT EDIT, v2.8.0, package clause) |
| `//tests:version_sync_test` | `private/versions.bzl` matches `go.mod` |
| `//tests/petstore:client_test` | generated client vs httptest: path params, bodies, 200/404/201, Date |
| `//tests/config:models_test` | config file, split spec via `$ref` + `data` + import-mapping `-` |
| `//tests/server:server_test` | generated strict server + generated client round trip; embedded spec |
| `e2e/consumer //api:client_test` | consumer module: own SDK (Go 1.25.14), own go_deps, shared runtime repo |

### Bumping oapi-codegen

`tools/update_versions.sh <codegen version> [<runtime version>]`, then update
the version strings in `README.md`, `DESIGN.md` and `tests/assert_generated.sh`
(the script already rewrites `go.mod`, `go.sum` and `private/versions.bzl`).

### Style

- All `.bzl` files use 4-space indentation.
- Public rules/macros have docstrings and attribute docs.
- `private/` contains implementation details; only `defs.bzl` is the stable API.
- `MODULE.bazel.lock` is not committed.

## Known limitations

- **No Windows exec platforms** — the action runs under a POSIX shell.
- **macOS unvalidated** — nothing Linux-specific, but no CI coverage.
- **External `$ref` files need a config** with `import-mapping`
  (oapi-codegen requirement); list the files in `data`.
- **No server macro** — generate servers with `oapi_codegen` + your own
  `go_library` (see `tests/server`).

## Release archive

`.gitattributes` export-ignores `tests/`, so it may load dev-only modules; nothing else may. CI's `consumer` job checks that `@rules_oapi_codegen//...` loads from the commit's `git archive` (`.github/consumer/check.sh`).
