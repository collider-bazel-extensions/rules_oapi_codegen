"""go_oapi_client — oapi_codegen + go_library in one call.

Generates `<name>.gen.go` from the spec and compiles it into a go_library
named `<name>`, linked against oapi-codegen's runtime packages. Depend on it
like any other go_library.
"""

load("@rules_go//go:def.bzl", "go_library")
load(":oapi_codegen.bzl", "oapi_codegen")

# Generated clients import these; types-only output may use neither, which
# go_library tolerates.
_RUNTIME_DEPS = [
    Label("@com_github_oapi_codegen_runtime//:runtime"),
    Label("@com_github_oapi_codegen_runtime//types"),
]

def _default_package(importpath):
    last = importpath.rstrip("/").split("/")[-1]
    return last.replace("-", "_").replace(".", "_")

def go_oapi_client(
        name,
        spec,
        importpath,
        package = None,
        generate = ["types", "client"],
        config = None,
        data = [],
        deps = [],
        **kwargs):
    """Generates a Go client from an OpenAPI spec and wraps it in a go_library.

    Args:
      name: Name of the go_library. The codegen target is `<name>_gen`.
      spec: The OpenAPI 3.0 spec (YAML or JSON).
      importpath: Go import path of the generated library.
      package: Go package name. Defaults to the last element of `importpath`,
        with `-` and `.` replaced by `_`.
      generate: oapi-codegen `-generate` targets. Defaults to
        `["types", "client"]`. Pass `[]` to take them from `config`.
      config: Optional oapi-codegen config file. Must not set `output:`.
      data: Files the spec references through `$ref`.
      deps: Extra go_library deps, added to oapi-codegen's runtime packages.
      **kwargs: Passed to go_library (`visibility`, `tags`, ...).
        `visibility`, `tags`, `testonly` and `target_compatible_with` also
        apply to `<name>_gen`, so the generated file can be inspected or
        reused.
    """
    gen_kwargs = {
        k: kwargs[k]
        for k in ["visibility", "tags", "testonly", "target_compatible_with"]
        if k in kwargs
    }
    oapi_codegen(
        name = name + "_gen",
        spec = spec,
        package = package or _default_package(importpath),
        generate = generate,
        config = config,
        data = data,
        out = name + ".gen.go",
        **gen_kwargs
    )
    go_library(
        name = name,
        srcs = [":" + name + "_gen"],
        importpath = importpath,
        deps = _RUNTIME_DEPS + [
            d
            for d in deps
            if native.package_relative_label(d) not in _RUNTIME_DEPS
        ],
        **kwargs
    )
