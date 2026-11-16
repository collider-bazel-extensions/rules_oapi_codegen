"""Repositories for ts_oapi_types: a pinned Node.js binary per platform and
the npm packages from private/npm/package-lock.json.

Both come from the `ts_deps` module extension. Repositories are fetched
lazily, so a build that never analyses a ts_oapi_types target (for example
one that only uses go_oapi_client) downloads none of this.
"""

NODE_VERSION = "24.22.2"

# https://nodejs.org/dist/v24.22.2/SHASUMS256.txt
_NODE_PLATFORMS = {
    "darwin_amd64": ("darwin-x64", "6965578fd823e72c1b5387f5ab84cb25368f886e02eb8779e6f0fce6b91c27b7"),
    "darwin_arm64": ("darwin-arm64", "1f5ac075be50bed4780ea3be19a007fda95ea4d527d28d76d0b91de47d915115"),
    "linux_amd64": ("linux-x64", "48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75"),
    "linux_arm64": ("linux-arm64", "eb187837a2230d4047161ac0be008584e16b46f726e9c9490ee35dc6b17d9ba8"),
}

NODE_REPO_PREFIX = "oapi_ts_node_"
NPM_REPO = "oapi_ts_npm"

def _node_repo_impl(rctx):
    stem = "node-v{}-{}".format(rctx.attr.version, rctx.attr.platform)
    rctx.download_and_extract(
        url = "https://nodejs.org/dist/v{}/{}.tar.xz".format(rctx.attr.version, stem),
        sha256 = rctx.attr.sha256,
        stripPrefix = stem,
    )
    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

exports_files(["bin/node"])

filegroup(
    name = "node",
    srcs = ["bin/node"],
)
""")

node_repo = repository_rule(
    implementation = _node_repo_impl,
    doc = "One Node.js release binary, sha256-pinned.",
    attrs = {
        "platform": attr.string(mandatory = True, doc = "nodejs.org platform, e.g. linux-x64."),
        "sha256": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
    },
)

def _npm_repo_impl(rctx):
    lock = json.decode(rctx.read(rctx.attr.lock))
    if lock.get("lockfileVersion") != 3:
        fail("{}: want lockfileVersion 3, got {}".format(rctx.attr.lock, lock.get("lockfileVersion")))
    for i, (path, pkg) in enumerate(sorted(lock["packages"].items())):
        if not path.startswith("node_modules/"):
            continue  # "" is the root project
        if pkg.get("link"):
            fail("{}: {} is a link; only registry packages are supported".format(rctx.attr.lock, path))
        if "os" in pkg or "cpu" in pkg:
            fail("{}: {} is platform-specific (os/cpu); the npm tree is shared by every exec platform".format(rctx.attr.lock, path))
        integrity = pkg.get("integrity", "")
        if not integrity.startswith("sha512-"):
            fail("{}: {} has no sha512 integrity".format(rctx.attr.lock, path))

        # npm tarballs nearly always unpack to package/, but not all do.
        # Unpack to a scratch dir, find the single top-level directory, and
        # extract again from it into the install path.
        archive = "_tgz/{}.tgz".format(i)
        rctx.download(url = pkg["resolved"], output = archive, integrity = integrity)
        probe = "_probe/{}".format(i)
        rctx.extract(archive, output = probe)
        tops = rctx.path(probe).readdir()
        if len(tops) != 1:
            fail("{}: {} unpacks to {} entries, want one directory".format(rctx.attr.lock, path, len(tops)))
        rctx.extract(archive, output = path, stripPrefix = tops[0].basename)
        rctx.delete(probe)
        rctx.delete(archive)
    rctx.delete("_tgz")
    rctx.delete("_probe")

    rctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "node_modules",
    srcs = glob(["node_modules/**"]),
)

exports_files([
    "node_modules/openapi-typescript/package.json",
    "node_modules/typescript/lib/tsc.js",
])
""")

npm_repo = repository_rule(
    implementation = _npm_repo_impl,
    doc = "Lays out an npm package-lock.json (v3) as node_modules/, " +
          "each tarball checked against the lock's sha512 integrity.",
    attrs = {
        "lock": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _ts_deps_impl(mctx):
    for name, (platform, sha256) in _NODE_PLATFORMS.items():
        node_repo(
            name = NODE_REPO_PREFIX + name,
            platform = platform,
            sha256 = sha256,
            version = NODE_VERSION,
        )
    npm_repo(
        name = NPM_REPO,
        lock = Label("//private/npm:package-lock.json"),
    )
    return mctx.extension_metadata(reproducible = True)

ts_deps = module_extension(
    implementation = _ts_deps_impl,
    doc = "Node.js and the pinned npm tree for ts_oapi_types. No tags.",
)
