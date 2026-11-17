# rules_oapi_codegen

Hermetic OpenAPI 3 code generation for Bazel: Go through
[oapi-codegen](https://github.com/oapi-codegen/oapi-codegen), TypeScript
through [openapi-typescript](https://openapi-ts.dev). One spec, both sides.
Three entry points:

- **`oapi_codegen`** — runs oapi-codegen over a spec and declares the
  generated `.go` file as its output. Feed it to any `go_library`.
- **`go_oapi_client`** — `oapi_codegen` + `go_library` in one call, linked
  against oapi-codegen's runtime packages. Depend on it like any Go library.
- **`ts_oapi_types`** — one `.ts` module: openapi-typescript's types
  (`paths`, `components`, `operations`) plus a runtime `operationMap`
  (operationId → method and path) and per-operation helper types. A plain
  source file for `ts_project` or any TypeScript rule.

oapi-codegen is built from source with rules_go at the version pinned in
`go.mod`. Codegen needs no host Go: the action runs the rules_go SDK's `go`
for oapi-codegen's goimports pass. `ts_oapi_types` needs no host Node.js:
it runs a sha256-pinned Node.js over npm packages pinned by a
`package-lock.json`, and Go-only users never download either.

**Supported platforms:** Linux and macOS exec platforms; amd64 and arm64
for `ts_oapi_types` (pinned Node.js builds). Linux amd64 validated in CI;
macOS pending. No Windows. See [Contributing](#contributing).

**Pinned versions:** oapi-codegen v2.8.0, oapi-codegen/runtime v1.6.0,
built and tested with Go 1.26.10 (minimum Go 1.25). openapi-typescript
7.13.0 on Node.js 24.22.2; generated TypeScript tested with TypeScript 5.9.3.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Rules](#rules)
  - [go\_oapi\_client](#go_oapi_client)
  - [oapi\_codegen](#oapi_codegen)
  - [ts\_oapi\_types](#ts_oapi_types)
- [Go SDK and Go dependencies](#go-sdk-and-go-dependencies)
- [Node.js and npm packages](#nodejs-and-npm-packages)
- [Running oapi-codegen directly](#running-oapi-codegen-directly)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Contributing](#contributing)

---

## Installation

```python
bazel_dep(name = "rules_oapi_codegen", version = "0.2.1")
```

`rules_oapi_codegen` is **Bzlmod-only**. Until it lands in BCR, consume it
via `archive_override` pointing at a release tag:

```python
bazel_dep(name = "rules_oapi_codegen", version = "0.2.1")
archive_override(
    module_name = "rules_oapi_codegen",
    urls = ["https://github.com/collider-bazel-extensions/rules_oapi_codegen/archive/refs/tags/v0.2.1.tar.gz"],
    strip_prefix = "rules_oapi_codegen-0.2.1",
    integrity = "sha256-8pmprzlADg1adq+7OjBawALzlvjbJvTqLtiSYGT7Z3c=",
)
```

The release archive (the tag tarball) leaves out `tests/`, whose packages load the dev-only `rules_shell`, so `bazel query @rules_oapi_codegen//...` works for consumers (since v0.1.1). A `git_override` clone still contains it; name packages instead (for example `@rules_oapi_codegen//:all`).

It depends on `rules_go` (>= 0.59.0), `gazelle` (>= 0.50.0), `bazel_skylib`
and `platforms`. Your module needs `rules_go` anyway to build the generated
Go code. `ts_oapi_types` adds no module dependency: no rules_js, rules_ts or
rules_nodejs (see [Node.js and npm packages](#nodejs-and-npm-packages)).

---

## Quickstart

```
packages/api-client/
  openapi.yaml
  BUILD.bazel
```

```python
load("@rules_oapi_codegen//:defs.bzl", "go_oapi_client")

go_oapi_client(
    name = "api",
    spec = "openapi.yaml",
    importpath = "example.com/myrepo/packages/api-client",
    visibility = ["//visibility:public"],
)
```

```go
import client "example.com/myrepo/packages/api-client"

c, err := client.NewClientWithResponses("https://api.example.com")
resp, err := c.GetPetWithResponse(ctx, 42)
// resp.JSON200 is a *client.Pet
```

`bazel build //packages/api-client:api` generates `api.gen.go` and compiles
it. The generated file is also available as `:api_gen`, if you want to look
at it (`bazel build //packages/api-client:api_gen`).

TypeScript from the same spec (for example a TS server's REST gateway):

```python
load("@aspect_rules_ts//ts:defs.bzl", "ts_project")
load("@rules_oapi_codegen//:defs.bzl", "ts_oapi_types")

ts_oapi_types(
    name = "api_ts",                 # outputs api_ts.ts
    spec = "openapi.yaml",
)

ts_project(
    name = "gateway",
    srcs = ["gateway.ts", ":api_ts"],
    # ...
)
```

```ts
import { operationMap, type OperationRequestBody, type OperationResponseBody } from "./api_ts";

operationMap.getPet;                       // { method: "get", path: "/pets/{petId}" }
type Pet = OperationResponseBody<"getPet", 200>;
type NewPet = OperationRequestBody<"createPet">;
```

---

## Rules

### `go_oapi_client`

Macro: `oapi_codegen` (named `<name>_gen`, output `<name>.gen.go`) plus a
`go_library` named `<name>`.

```python
go_oapi_client(
    name = "api",
    spec = "openapi.yaml",
    importpath = "example.com/myrepo/api",
    package = "api",                  # optional
    generate = ["types", "client"],   # default
    config = "oapi-codegen.yaml",     # optional
    data = ["schemas/common.yaml"],   # optional: files reached by $ref
    deps = [],                        # optional: extra go_library deps
)
```

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name of the `go_library`. The codegen target is `<name>_gen`. |
| `spec` | `label` | required | OpenAPI 3.0 spec, `.yaml`/`.yml`/`.json`. |
| `importpath` | `string` | required | Go import path of the library. |
| `package` | `string` | last element of `importpath` | Go package name. `-` and `.` become `_`. |
| `generate` | `string_list` | `["types", "client"]` | oapi-codegen `-generate` targets. Pass `[]` to take them from `config`. |
| `config` | `label` | `None` | oapi-codegen config file. Must not set `output:`. |
| `data` | `label_list` | `[]` | Files the spec references through `$ref`. |
| `deps` | `label_list` | `[]` | Extra `go_library` deps, added to `@com_github_oapi_codegen_runtime//:runtime` and `//types`. |
| `**kwargs` | | | Passed to `go_library`. `visibility`, `tags`, `testonly` and `target_compatible_with` also apply to `<name>_gen`. |

### `oapi_codegen`

Runs

```
oapi-codegen [-config <config>] [-package <package>] [-generate <a,b,...>] -o <out> <spec>
```

and outputs one Go file. Use it directly to generate servers, to split a spec
across several generated files in one package, or to control the
`go_library` yourself.

```python
load("@rules_go//go:def.bzl", "go_library")
load("@rules_oapi_codegen//:defs.bzl", "oapi_codegen")

oapi_codegen(
    name = "server_gen",
    spec = "openapi.yaml",
    package = "api",
    generate = ["types", "std-http-server", "strict-server", "spec"],
)

go_library(
    name = "api",
    srcs = [":server_gen"],
    importpath = "example.com/myrepo/api",
    deps = [
        "@com_github_getkin_kin_openapi//openapi3",  # for `spec`
        "@com_github_oapi_codegen_runtime//:runtime",
        "@com_github_oapi_codegen_runtime//strictmiddleware/nethttp",
    ],
)
```

Which runtime packages a server needs depends on the `generate` targets;
list them in your own `go.mod` and `use_repo` them from your `go_deps`.

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `spec` | `label` | required | OpenAPI 3.0 spec, `.yaml`/`.yml`/`.json`. |
| `package` | `string` | `""` | Go package (`-package`). Required unless `config` sets `package:`; overrides it when both are set. |
| `generate` | `string_list` | `[]` | `-generate` targets. With no `config`, empty means `["types", "client"]`; with a `config`, empty means "whatever the config says". When set, overrides the config. |
| `config` | `label` | `None` | oapi-codegen config file (`-config`). Must not set `output:`. |
| `data` | `label_list` | `[]` | Files the spec references through `$ref`, at the same relative paths as in the source tree. |
| `out` | `string` | `<name>.gen.go` | Output file name. |

**Config files.** Everything oapi-codegen's config supports works
(`output-options`, `compatibility`, `import-mapping`, ...), except `output:`.
oapi-codegen gives a config's `output:` precedence over `-o`, so the file
would land where Bazel isn't looking. The action fails if the declared output
is missing and names that key.

**Specs split across files.** oapi-codegen needs an `import-mapping` for
every external `$ref` file, which only a config file can provide. To
generate both files into one Go package, map the file to `-` and generate it
with a second `oapi_codegen` target. A spec with no paths needs
`output-options: skip-prune: true`, or oapi-codegen prunes all of its
schemas. `tests/config/` has a worked example.

### `ts_oapi_types`

Generates one TypeScript module (`<name>.ts`) from an OpenAPI 3.0 / 3.1 spec
with openapi-typescript 7.13.0, followed by an operations map.

```python
ts_oapi_types(
    name = "api_ts",
    spec = "openapi.yaml",
    data = ["schemas/common.yaml"],   # optional: files reached by $ref
    out = "api.gen.ts",               # optional, default <name>.ts
)
```

**Attributes:**

| Attribute | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Target name. |
| `spec` | `label` | required | OpenAPI 3.0 / 3.1 spec, `.yaml`/`.yml`/`.json`. |
| `data` | `label_list` | `[]` | Files the spec references through `$ref`, at the same relative paths as in the source tree. |
| `out` | `string` | `<name>.ts` | Output file name; must end in `.ts`. |

The output is the target's only file (`DefaultInfo`), so `ts_project(srcs =
[":api_ts"])` takes it like a source file; no rules_js provider is involved.
It is a `.ts` (not `.d.ts`) because `operationMap` is a runtime value. It
compiles under `--strict`, `--isolatedModules`, `--verbatimModuleSyntax`,
`--erasableSyntaxOnly`, `--exactOptionalPropertyTypes` and
`--noUncheckedIndexedAccess`, and Node.js can run it with type stripping.

**What the module exports.**

1. openapi-typescript's output, unchanged and with its default options:
   `paths`, `webhooks`, `components`, `$defs` and `operations` (one entry
   per operation with an `operationId`).
2. `operationMap`: every operation with an `operationId`, in spec order,
   `as const`. Methods are lower case, as in `paths`.

   ```ts
   export const operationMap = {
       listPets: { method: "get", path: "/pets" },
       getPet: { method: "get", path: "/pets/{petId}" },
       "update-pet": { method: "patch", path: "/pets/{petId}" },
   } as const;
   ```

3. Helper types, all keyed by operationId and indexing `operations`:

   | Type | Is |
   |---|---|
   | `OperationId` | `keyof typeof operationMap` |
   | `OperationMethod<Id>`, `OperationPath<Id>` | the literal method / path template (`paths[OperationPath<Id>][OperationMethod<Id>]` is `operations[Id]`) |
   | `OperationParameters<Id>` | `operations[Id]["parameters"]` |
   | `OperationPathParams<Id>`, `OperationQueryParams<Id>`, `OperationHeaderParams<Id>` | that parameter group, `undefined` when the operation has none |
   | `OperationRequestBody<Id>` | the body type (union over media types); `never` without a request body |
   | `OperationResponses<Id>` | `operations[Id]["responses"]`, keyed by status code or `default` |
   | `OperationResponseBody<Id, Status>` | that response's body type; `never` when it has no content |

Operations without an `operationId` are typed under `paths` but are not in
`operationMap`.

**Errors.** An invalid spec fails the action with `ts_oapi_types: <spec>:
<reason>`, for example an unresolvable `$ref` (with its JSON pointer), a
duplicate `operationId`, YAML syntax errors, or a Swagger 2.0 document.

**openapi-typescript options** (`--enum`, `--immutable`, ...) are not exposed
yet; the defaults apply.

---

## Go SDK and Go dependencies

**Go SDK.** rules_oapi_codegen registers Go 1.26.10 with
`go_sdk.download`. If your root module registers its own SDK, yours is used.
oapi-codegen v2.8 needs Go >= 1.25.

**Go modules.** rules_oapi_codegen declares oapi-codegen and its runtime in
its own `go.mod`, read by gazelle's `go_deps`. `go_deps` merges every
module's `go.mod` with minimal version selection, so:

- `go_oapi_client` resolves the runtime repo on its own; you don't need to
  `use_repo` it unless your code imports it directly.
- If your `go.mod` requires `github.com/oapi-codegen/runtime` (or any
  oapi-codegen dependency) at a higher version, that version is used for
  both. Generated code from v2.8.0 needs runtime >= v1.6.0.
- The repos are shared: `@com_github_oapi_codegen_runtime//types` in your
  BUILD files is the same target `go_oapi_client` links against.

---

## Node.js and npm packages

`ts_oapi_types` runs Node.js and openapi-typescript without rules_js:

- **Node.js 24.22.2**, the official nodejs.org build for the exec platform
  (linux and darwin, x64 and arm64), each pinned by sha256
  (`private/ts_deps.bzl`).
- **npm packages** from `private/npm/package-lock.json` (lockfileVersion 3):
  a repository rule downloads every `packages["node_modules/..."]` tarball
  from its `resolved` URL, checks it against the lock's sha512 `integrity`,
  and unpacks it at that install path. No npm, no install scripts, no
  network in the build action. The lock holds openapi-typescript 7.13.0 and
  its dependencies, plus TypeScript 5.9.3 (openapi-typescript's peer
  dependency, also used by this repo's typecheck test).

Both come from a module extension inside rules_oapi_codegen (nothing for you
to configure). Repositories are fetched lazily, and only the exec
platform's Node.js is selected, so a build that uses only `go_oapi_client` /
`oapi_codegen` downloads no Node.js and no npm package. Your own Node.js or
rules_js setup, if any, is independent of this one.

---

## Running oapi-codegen directly

The pinned binary is a regular target:

```sh
bazel run @rules_oapi_codegen//:oapi-codegen -- -version
```

Running it this way formats output only if a `go` is on PATH. Inside Bazel
actions, use `oapi_codegen`.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| oapi-codegen | Fully hermetic. Built from source at the version (and go.sum hash) pinned in `go.mod`. | Bump with `tools/update_versions.sh`. Generated headers name that version (`private/versions.bzl`). |
| `go` for goimports | Fully hermetic. The rules_go SDK's `go`, with `GOTOOLCHAIN=local`, `GOPROXY=off`, `GOENV=off`, `GOWORK=off`. | No host Go needed. |
| Shell | The action runs under `/bin/bash` (Bazel's default shell). | No Windows exec platforms. |
| Spec inputs | `spec`, `config` and `data` only. | Undeclared `$ref` targets are not in the sandbox, so codegen fails. |
| Node.js (`ts_oapi_types`) | Fully hermetic. nodejs.org release binary, sha256-pinned per platform. | The action runs it directly: no shell, a fixed two-variable environment, `block-network`. |
| openapi-typescript and deps | Fully hermetic. Every tarball checked against `package-lock.json`'s sha512 integrity. | Regenerate the lock with `tools/update_npm_lock.sh` (needs host npm, maintainer-time only). |

---

## Contributing

PRs welcome. Conventions match the sibling rule sets:

- New behaviour needs an analysis test in `tests/analysis_tests.bzl` or an
  end-to-end test under `tests/`.
- Changes that affect how consumers resolve the module also need
  `e2e/consumer` to pass (`cd e2e/consumer && bazel test //...`).
- Bumping oapi-codegen or its runtime: `tools/update_versions.sh <codegen
  version> [<runtime version>]`.
- Bumping openapi-typescript or TypeScript: `tools/update_npm_lock.sh
  <openapi-typescript version> [<typescript version>]`, then refresh
  `tests/ts/petstore.ts.golden` (the golden test prints the command).
  Bumping Node.js: `NODE_VERSION` and the four sha256s in
  `private/ts_deps.bzl`, from nodejs.org's `SHASUMS256.txt`.
- `MODULE.bazel.lock` is intentionally not committed.

### Help wanted: macOS validation

Nothing in the rules is Linux-specific (`ts_oapi_types` pins darwin Node.js
builds too), but no one has run the tests on Darwin yet. A pasted log from a green `bazel test //...` on macOS would
unblock the macOS support claim.

---

## Requesting a new rules package

Want Bazel rules for another tool or service?
[Request a rules package](https://github.com/collider-bazel-extensions/.github/issues/new?template=request-a-rules-package.yml).
The [organization page](https://github.com/collider-bazel-extensions) lists every package.

## License

[Apache License 2.0](LICENSE) (SPDX: `Apache-2.0`).
