"""Analysis-time tests. Verify the rules' outputs and argument validation
without running oapi-codegen."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_oapi_codegen//:defs.bzl", "go_oapi_client", "oapi_codegen")

def _single_output_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    files = target[DefaultInfo].files.to_list()
    asserts.equals(env, 1, len(files), "expected exactly one output")
    asserts.equals(env, ctx.attr.expected_basename, files[0].basename)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "OapiCodegen"]
    asserts.equals(env, 1, len(actions), "expected one OapiCodegen action")
    argv = actions[0].argv
    for flag in ctx.attr.expected_args:
        asserts.true(env, flag in argv, "expected {} in argv {}".format(flag, argv))
    for flag in ctx.attr.unexpected_args:
        asserts.false(env, flag in argv, "did not expect {} in argv {}".format(flag, argv))
    return analysistest.end(env)

_single_output_test = analysistest.make(
    _single_output_impl,
    attrs = {
        "expected_basename": attr.string(),
        "expected_args": attr.string_list(),
        "unexpected_args": attr.string_list(),
    },
)

def _fails_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_message)
    return analysistest.end(env)

_fails_test = analysistest.make(
    _fails_impl,
    expect_failure = True,
    attrs = {"expected_message": attr.string()},
)

def oapi_codegen_test_suite(name):
    """Output naming, flag assembly and validation for oapi_codegen."""
    spec = "//tests/petstore:openapi.yaml"

    # Defaults: <name>.gen.go, `-generate types,client` when there is no config.
    oapi_codegen(name = name + "_defaults", spec = spec, package = "p", tags = ["manual"])
    _single_output_test(
        name = name + "_defaults_test",
        target_under_test = ":" + name + "_defaults",
        expected_basename = name + "_defaults.gen.go",
        expected_args = ["-package", "p", "-generate", "types,client"],
        unexpected_args = ["-config"],
    )

    # `out` renames the file; `generate` is passed through.
    oapi_codegen(
        name = name + "_out",
        spec = spec,
        package = "p",
        generate = ["types", "std-http-server", "spec"],
        out = "api.go",
        tags = ["manual"],
    )
    _single_output_test(
        name = name + "_out_test",
        target_under_test = ":" + name + "_out",
        expected_basename = "api.go",
        expected_args = ["-generate", "types,std-http-server,spec"],
    )

    # With a config file and no `generate`, the config decides: no -generate,
    # and no -package when `package` is unset.
    oapi_codegen(
        name = name + "_config",
        spec = "//tests/config:openapi.yaml",
        config = "//tests/config:oapi-codegen.yaml",
        data = ["//tests/config:errors.yaml"],
        tags = ["manual"],
    )
    _single_output_test(
        name = name + "_config_test",
        target_under_test = ":" + name + "_config",
        expected_basename = name + "_config.gen.go",
        expected_args = ["-config"],
        unexpected_args = ["-generate", "-package"],
    )

    # No package and no config is an analysis error.
    oapi_codegen(name = name + "_nopkg", spec = spec, tags = ["manual"])
    _fails_test(
        name = name + "_nopkg_test",
        target_under_test = ":" + name + "_nopkg",
        expected_message = "set `package`, or pass a `config` that sets `package:`",
    )

    native.test_suite(name = name, tests = [
        ":" + name + "_defaults_test",
        ":" + name + "_out_test",
        ":" + name + "_config_test",
        ":" + name + "_nopkg_test",
    ])

def go_oapi_client_test_suite(name):
    """go_oapi_client wires `<name>_gen` -> `<name>.gen.go`, package from importpath."""
    go_oapi_client(
        name = name + "_subject",
        spec = "//tests/petstore:openapi.yaml",
        importpath = "example.com/my-api.v1",
        tags = ["manual"],
    )
    _single_output_test(
        name = name + "_gen_test",
        target_under_test = ":" + name + "_subject_gen",
        expected_basename = name + "_subject.gen.go",
        expected_args = ["-package", "my_api_v1", "-generate", "types,client"],
    )
    native.test_suite(name = name, tests = [":" + name + "_gen_test"])
