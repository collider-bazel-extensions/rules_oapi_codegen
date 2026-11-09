# rules_oapi_codegen — design decisions

Hermetic [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) for
Bazel: `oapi_codegen` (OpenAPI 3 spec → one `.go` file) and `go_oapi_client`
(`oapi_codegen` + `go_library`). A build-time code generator, with no cluster
and no network at build time.

Requested in rules_atlas#4 for monok8s, which generates its Go API client
from `packages/api-client/openapi.yaml`. Same family as `rules_opa` and
`rules_helm` (CLI rules over pinned tools), not the in-cluster operator
rules.

## Decided

| # | Decision | Choice | Source |
|---|---|---|---|
| 1 | Bzlmod / WORKSPACE | **Bzlmod-only at v0.1.** `WORKSPACE` and `repositories.bzl` are stubs. | Sibling-family precedent |
| 2 | Binary provisioning | **Build oapi-codegen from source** with rules_go, at the version pinned in `go.mod` (hash-pinned by `go.sum`). oapi-codegen publishes no release binaries, and a Go tool built from source is as hermetic as a sha256-pinned download. | oapi-codegen-specific |
| 3 | Go module resolution | gazelle `go_deps.from_file(go_mod = "//:go.mod")`. Consumers' `go.mod` files merge with ours by MVS, so the runtime repo they import and the one `go_oapi_client` links are the same. | rules_go ecosystem norm |
| 4 | No module extension / toolchain | Nothing to download per platform: the tool is a `go_binary` built for the exec platform, so a toolchain type would add nothing. `//:oapi-codegen` is an alias to it. | Smallest viable |
| 5 | Custom rule, not `run_binary` | oapi-codegen formats output with `golang.org/x/tools/imports`, which runs `go env`. The action must put the rules_go SDK's `go` on PATH and set `GOROOT`; `run_binary` can't. `oapi_codegen` resolves `@rules_go//go:toolchain` and runs a short `run_shell` command. | Hermeticity |
| 6 | Go environment in the action | `GOTOOLCHAIN=local GOPROXY=off GOENV=off GOWORK=off GOFLAGS=`, with `GOCACHE`/`GOPATH` under the output's path, removed afterwards. No host Go, no network, no user `go.env`. | Hermeticity |
| 7 | Inputs | `sdk.go` and `sdk.root_file` only, not the whole SDK. `go env` needs nothing else; goimports only resolves imports for unresolved identifiers, which generated code doesn't have. | Measured |
| 8 | Config `output:` | oapi-codegen lets a config's `output:` beat `-o`. The rule can't rewrite YAML portably, so the action checks the declared output exists and fails naming the key. | oapi-codegen CLI (`updateConfigFromFlags`) |
| 9 | Flag precedence | `package` and `generate` attributes, when set, override the config (oapi-codegen's own flag-over-config order). Without a config, `package` is required (analysis error) and `generate` defaults to `types,client`. | oapi-codegen CLI |
| 10 | Split specs | `data` declares `$ref` targets so they're in the sandbox at the same relative paths. Mapping them to a package is oapi-codegen's `import-mapping`, which is config-only; not wrapped. | oapi-codegen-specific |
| 11 | `go_oapi_client` | Macro: `<name>_gen` (`oapi_codegen`, output `<name>.gen.go`) + `go_library` `<name>`. Default deps `runtime` + `runtime/types`; user `deps` deduplicated against them by resolved label. `visibility`/`tags`/`testonly`/`target_compatible_with` apply to both targets. Package defaults to the last `importpath` element with `-`/`.` → `_`. | Requester's API |
| 12 | Pinned versions | oapi-codegen v2.8.0, runtime v1.6.0: the versions monok8s tested against. v2.8.1 / runtime v1.8.0 were a week old at v0.1.0. | Downstream |
| 13 | rules_go / gazelle minimums | **rules_go 0.59.0, gazelle 0.50.0.** `bazel_dep` versions are minimums every consumer inherits. rules_go 0.65.0 was tried first: its `go.mod` requires `golang.org/x/mod` v0.41.0, which `go_deps` folds into every consumer's graph and which needs Go ≥ 1.26, so a consumer on Go 1.25 failed to build oapi-codegen. 0.59.0 / 0.50.0 match monok8s and work on Bazel 8 and 9. | Measured (e2e/consumer) |
| 14 | Go SDK | `go_sdk.download(version = "1.26.10")`. A root module's own SDK takes precedence. oapi-codegen v2.8 needs Go ≥ 1.25; e2e/consumer pins 1.25.14 to keep that floor tested. | rules_go behaviour |
| 15 | Platforms | Linux and macOS exec platforms (POSIX shell in the action). No Windows. Linux validated in CI. | Sibling family |
| 16 | Tests | Analysis tests (output naming, argv per attribute, validation); end-to-end client against httptest (`tests/petstore`); config + split spec (`tests/config`); generated strict server called by the generated client (`tests/server`); generated-file header check; `versions.bzl`/`go.mod` sync check; a separate consumer module (`e2e/consumer`) with its own Go SDK and `go_deps`. | Sibling family + requester |
| 17 | CI | Bazel 8.x and 9.x matrix. Host Go is removed first: PATH entries holding `go` are dropped, and `go`/`gofmt` are deleted from `/bin`, `/usr/bin`, `/usr/local/bin` (Bazel's default action PATH, which the job PATH doesn't control). Green CI proves codegen doesn't touch host Go. | rules_spicedb hermetic-verification pattern |
| 18 | License | None, matching the sibling repos. | Org precedent |

## Notes

- `bazel run //:oapi-codegen` works, but outside an action nothing puts `go`
  on PATH, so goimports formatting needs a host Go. Inside Bazel, use
  `oapi_codegen`.
- **Generated header.** oapi-codegen reads its module path and version from
  Go build info. rules_go < 0.60 doesn't embed it, so the header would read
  "Code generated by unknown module path version unknown version". Fixing it
  in the binary means `x_defs` on oapi-codegen's `main` package, but gazelle
  makes that `go_library` private and `go_deps` overrides are only reliable
  from the root module. So the action rewrites that exact line to
  `github.com/oapi-codegen/oapi-codegen/v2 version <OAPI_CODEGEN_VERSION>`
  (`private/versions.bzl`). Under a rules_go that embeds build info the string
  never appears and the rewrite does nothing. `//tests:version_sync_test`
  keeps `versions.bzl` equal to `go.mod`; `tests/assert_generated.sh` checks
  the header.
- `GOCACHE`/`GOPATH` live next to the output (`<out>.gocache`, `<out>.gopath`)
  rather than in `$TMPDIR`, so parallel actions never share them, and are
  deleted before the action ends.

## v0.1.0 status

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only), go.mod / go.sum | done |
| `oapi_codegen` rule, `go_oapi_client` macro | done |
| `//:oapi-codegen` from source | done |
| Analysis + end-to-end tests (client, config, split spec, server), e2e consumer | done (Linux) |
| CI (Bazel 8.x + 9.x, no host Go) | done |
| macOS validation | pending |

## Deferred (not v0.1.0)

- **`go_oapi_server`** — macro for the server side. The deps depend on the
  router (`std-http-server`, `chi-server`, `echo-server`, ...), so v0.1 leaves
  server `go_library`s to the user (README example, `tests/server`).
- **Config rewriting** — strip `output:` from a user config instead of
  failing. Needs a YAML-aware step; not worth it until someone hits it.
- **Overlays / user templates** — oapi-codegen's `output-options.overlay` and
  `user-templates` reference files by path; they work today if those files
  are passed in `data`, but nothing tests them.
- **BCR publication.**

## Release archive contents (v0.1.1)

`tests/` is `export-ignore` (`.gitattributes`): its packages load the dev-only `rules_shell`, which made `@rules_oapi_codegen//...` unloadable for consumers. GitHub's tag tarballs honour it; a `git_override` clone still contains it. `REPO.bazel` `ignore_directories` isn't used because it would also hide it from this repo's own `bazel test`. `e2e/` (a separate root module, not loaded by `//...`) and `tools/` (no BUILD files) still ship. CI's `consumer` job (`.github/consumer/check.sh`) queries `//...` from the commit's `git archive`. Same fix as rules_kubectl#5 / rules_atlas#12.
