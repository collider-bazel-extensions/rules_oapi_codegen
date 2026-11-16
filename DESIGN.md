# rules_oapi_codegen — design decisions

Hermetic [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) for
Bazel: `oapi_codegen` (OpenAPI 3 spec → one `.go` file) and `go_oapi_client`
(`oapi_codegen` + `go_library`); since v0.2.0 also `ts_oapi_types` (spec →
one `.ts` module through openapi-typescript). A build-time code generator,
with no cluster and no network at build time.

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
| 4 | No module extension / toolchain | Nothing to download per platform: the tool is a `go_binary` built for the exec platform, so a toolchain type would add nothing. `//:oapi-codegen` is an alias to it. (Go side only; `ts_oapi_types` has a module extension, #21–23.) | Smallest viable |
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
| 15 | Platforms | Linux and macOS exec platforms (POSIX shell in the action; `ts_oapi_types` has pinned Node.js for amd64 and arm64 of both). No Windows. Linux validated in CI. | Sibling family |
| 16 | Tests | Analysis tests (output naming, argv per attribute, validation); end-to-end client against httptest (`tests/petstore`); config + split spec (`tests/config`); generated strict server called by the generated client (`tests/server`); generated-file header check; `versions.bzl`/`go.mod` sync check; a separate consumer module (`e2e/consumer`) with its own Go SDK and `go_deps`. Since v0.2.0: `ts_oapi_types` analysis tests, golden output, invalid-spec errors, `tsc --noEmit --strict` + Node.js runtime check of `operationMap` (`tests/ts`), rules_ts `ts_project` in `e2e/consumer`, Go-only no-fetch check. | Sibling family + requester |
| 17 | CI | Bazel 8.x and 9.x matrix. Host Go and (since v0.2.0) host Node.js are removed first: PATH entries holding `go` are dropped, and `go`/`gofmt` are deleted from `/bin`, `/usr/bin`, `/usr/local/bin` (Bazel's default action PATH, which the job PATH doesn't control). Green CI proves codegen doesn't touch host Go or Node.js. Unprivileged user namespaces are enabled so linux-sandbox (and `block-network`) is used. | rules_spicedb hermetic-verification pattern |
| 18 | License | None, matching the sibling repos. | Org precedent |
| 19 | TypeScript generator | **openapi-typescript 7.13.0** (issue #1). The de facto OpenAPI → TS types generator; handles 3.0 and 3.1, `$ref` bundling (Redocly) and validation. Called through its JS API from `private/ts_oapi_types.mjs`, not its CLI, so the same bundled document also feeds the operations map. Default options; none exposed yet. | Requester (monok8s TS server) |
| 20 | Output shape | One `.ts` file in `DefaultInfo`: openapi-typescript's output verbatim, then `operationMap` (operationId → `{method, path}`, `as const`, spec order, lower-case methods) and helper types (`OperationId`, `OperationMethod/Path`, `OperationParameters`, `OperationPath/Query/HeaderParams`, `OperationRequestBody`, `OperationResponses`, `OperationResponseBody`) that index openapi-typescript's `operations`. `.ts`, not `.d.ts`, because the map is a runtime value; any TS rule (rules_ts `ts_project`) takes it as a source, with no rules_js provider. Indexing `operations[Id]` makes tsc reject a map entry openapi-typescript didn't type. | Issue #1: "operationId → method, path, params, request/response types" |
| 21 | Node.js | Official nodejs.org **24.22.2** (active LTS line, three weeks old at v0.2.0) `.tar.xz` per platform, sha256 from `SHASUMS256.txt`: linux/darwin × x64/arm64. `//private:node` selects one on the exec platform's `@platforms` constraints, so only that one is fetched. Not a toolchain: a registered toolchain is loaded by every toolchain resolution, Go-only builds included. | Hermeticity + "don't make Go consumers pay" |
| 22 | npm packages | `private/npm/package-lock.json` (lockfileVersion 3, generated once by npm, committed; `tools/update_npm_lock.sh` regenerates it). `npm_repo` reads it with `json.decode`, downloads each `packages["node_modules/<path>"].resolved` with `integrity` (sha512 SRI; Bazel's downloader checks it, and the repository cache keys on it), and extracts it at `node_modules/<path>`. Tarballs whose top-level directory isn't `package/` are handled by probing. Platform-specific (`os`/`cpu`) packages, links and non-sha512 entries are refused: one tree serves every exec platform. No rules_js / rules_nodejs / aspect deps. | Requester's constraint |
| 23 | Lazy fetching | One module extension (`ts_deps`, no tags) defines the Node.js and npm repositories; `MODULE.bazel` `use_repo`s them. Nothing references them unless a `ts_oapi_types` target is analysed, so Go-only consumers never fetch them. `e2e/consumer/go_only_check.sh` checks this in a fresh output base, with a positive control. | Requester's constraint |
| 24 | Action | `ctx.actions.run` on the Node binary (no shell), `--preserve-symlinks --preserve-symlinks-main` so modules resolve within the sandbox's declared inputs (the whole `node_modules` filegroup) rather than via realpaths into the external repo, env `FORCE_COLOR=0 NO_COLOR=1`, `execution_requirements = {"block-network": ""}`. The generator imports openapi-typescript by path from that tree; nothing resolves from the host. | Hermeticity |
| 25 | TypeScript for tests | TypeScript 5.9.3 is openapi-typescript's peer dependency, so it is in the same lock; the typecheck test runs its `tsc.js` on the pinned Node.js (no rules_ts in this module). openapi-typescript 7 accepts TypeScript `^5.x`, so 5.9.3 (not 6.x / 7.x). `e2e/consumer` separately compiles the output with rules_ts `ts_project` (its own TypeScript), proving the DefaultInfo hand-off. | Simplest hermetic option |

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

## v0.2.0 status

| Area | State |
|---|---|
| `ts_oapi_types` rule (types + `operationMap` + helper types) | done |
| Pinned Node.js (4 platforms), npm tree from `package-lock.json` | done |
| Tests: analysis, golden, invalid specs, `tsc --noEmit --strict` + runtime check, e2e `ts_project`, Go-only no-fetch check, archive consumer builds `ts_oapi_types` | done (Linux amd64) |
| CI without host Go **or** host Node.js | done |
| macOS / arm64 validation | pending |

## v0.1.0 status

| Area | State |
|---|---|
| MODULE.bazel (Bzlmod-only), go.mod / go.sum | done |
| `oapi_codegen` rule, `go_oapi_client` macro | done |
| `//:oapi-codegen` from source | done |
| Analysis + end-to-end tests (client, config, split spec, server), e2e consumer | done (Linux) |
| CI (Bazel 8.x + 9.x, no host Go) | done |
| macOS validation | pending |

## Deferred

- **openapi-typescript options** (`enum`, `immutable`, `rootTypes`, ...).
  Every option changes the generated surface; none was asked for. A
  whitelisted `options` attribute would map onto the JS API.

- **`go_oapi_server`** — macro for the server side. The deps depend on the
  router (`std-http-server`, `chi-server`, `echo-server`, ...), so v0.1 leaves
  server `go_library`s to the user (README example, `tests/server`).
- **Config rewriting** — strip `output:` from a user config instead of
  failing. Needs a YAML-aware step; not worth it until someone hits it.
- **Overlays / user templates** — oapi-codegen's `output-options.overlay` and
  `user-templates` reference files by path; they work today if those files
  are passed in `data`, but nothing tests them.
- **BCR publication.**
- **Remote execution of `ts_oapi_types`.** Inputs are fully declared, but
  the Node.js repository is chosen for the exec platform's constraints;
  with an RBE pool on another OS/CPU this works only if the pool's platform
  carries the right `@platforms` constraints. Untested.

## Release archive contents (v0.1.1, v0.2.0)

`tests/` is `export-ignore` (`.gitattributes`): its packages load the dev-only `rules_shell`, which made `@rules_oapi_codegen//...` unloadable for consumers. GitHub's tag tarballs honour it; a `git_override` clone still contains it. `REPO.bazel` `ignore_directories` isn't used because it would also hide it from this repo's own `bazel test`. `e2e/` (a separate root module, not loaded by `//...`) and `tools/` (no BUILD files) still ship. CI's `consumer` job (`.github/consumer/check.sh`) queries `//...` from the commit's `git archive`. Same fix as rules_kubectl#5 / rules_atlas#12. Since v0.2.0 the archive ships `private/npm/` (the lock the npm repository reads) and the same job builds a `ts_oapi_types` target from the archive and checks its `operationMap`.
