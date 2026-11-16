"""ts_oapi_types — OpenAPI 3 spec → one TypeScript module.

The module holds openapi-typescript's output (`paths`, `components`,
`operations`, `webhooks`, `$defs`), followed by a runtime `operationMap`
(operationId → `{method, path}`, `as const`) and helper types that index
`operations` by operationId. See private/ts_oapi_types.mjs.

The action runs a sha256-pinned Node.js binary (exec platform) over
openapi-typescript from the pinned npm tree (private/npm/package-lock.json),
with no shell, an empty environment and the network blocked. Every input,
including the whole node_modules tree, is declared, and Node runs with
--preserve-symlinks so modules resolve inside the sandbox.

The output is a plain `.ts` file in DefaultInfo, so `ts_project(srcs = [...])`
(rules_ts) or any other TypeScript rule can consume it.
"""

def _impl(ctx):
    if ctx.attr.out and not ctx.attr.out.endswith(".ts"):
        fail("ts_oapi_types {}: `out` must end in .ts, got {}".format(ctx.label, ctx.attr.out))
    out = ctx.actions.declare_file(ctx.attr.out or ctx.label.name + ".ts")
    node = ctx.executable._node
    marker = ctx.file._openapi_typescript_pkg

    # <npm repo>/node_modules/openapi-typescript/package.json → <npm repo>/node_modules
    node_modules = marker.dirname.rsplit("/", 1)[0]

    args = ctx.actions.args()
    args.add("--preserve-symlinks")
    args.add("--preserve-symlinks-main")
    args.add(ctx.file._script)
    args.add(node_modules)
    args.add(ctx.file.spec)
    args.add(out)
    args.add(ctx.file.spec.short_path)

    ctx.actions.run(
        executable = node,
        arguments = [args],
        inputs = depset(
            [ctx.file.spec, ctx.file._script] + ctx.files.data,
            transitive = [ctx.attr._node_modules[DefaultInfo].files],
        ),
        outputs = [out],
        # No color codes in error messages.
        env = {"FORCE_COLOR": "0", "NO_COLOR": "1"},
        execution_requirements = {"block-network": ""},
        mnemonic = "TsOapiTypes",
        progress_message = "Generating TypeScript from OpenAPI spec %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

ts_oapi_types = rule(
    implementation = _impl,
    doc = "Generates a TypeScript module (types + operation map) from an " +
          "OpenAPI 3 spec with openapi-typescript.",
    attrs = {
        "spec": attr.label(
            allow_single_file = [".yaml", ".yml", ".json"],
            mandatory = True,
            doc = "The OpenAPI 3.0 / 3.1 spec (YAML or JSON).",
        ),
        "data": attr.label_list(
            allow_files = True,
            doc = "Other files the spec references through `$ref`, at the " +
                  "same relative paths as in the source tree.",
        ),
        "out": attr.string(
            doc = "Output file name. Defaults to `<name>.ts`. Must end in `.ts`.",
        ),
        "_node": attr.label(
            default = Label("//private:node"),
            executable = True,
            cfg = "exec",
            allow_single_file = True,
        ),
        "_node_modules": attr.label(
            default = Label("@oapi_ts_npm//:node_modules"),
            cfg = "exec",
        ),
        "_openapi_typescript_pkg": attr.label(
            default = Label("@oapi_ts_npm//:node_modules/openapi-typescript/package.json"),
            allow_single_file = True,
            cfg = "exec",
        ),
        "_script": attr.label(
            default = Label("//private:ts_oapi_types.mjs"),
            allow_single_file = True,
        ),
    },
)
