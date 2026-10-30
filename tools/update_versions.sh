#!/usr/bin/env bash
# Maintainer-time script: bump the oapi-codegen and/or oapi-codegen/runtime
# versions rules_oapi_codegen builds and links against.
#
#   tools/update_versions.sh <oapi-codegen version> [<runtime version>]
#   tools/update_versions.sh v2.8.1 v1.8.0
#
# Rewrites the two `require` lines in go.mod and OAPI_CODEGEN_VERSION in
# private/versions.bzl, then runs `go mod tidy` through the rules_go SDK (no
# host Go needed) to refresh go.sum and the indirect requirements.
# Afterwards: update the version strings in README.md, DESIGN.md and
# tests/assert_generated.sh, and run `bazel test //...` plus the e2e
# consumer.
set -euo pipefail

cd "$(dirname "$0")/.."

codegen="${1:?usage: $0 <oapi-codegen version> [<runtime version>]}"
runtime="${2:-}"

for v in "$codegen" ${runtime:+"$runtime"}; do
    [[ "$v" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "update_versions: bad version '$v' (want vX.Y.Z)" >&2; exit 1; }
done

sed -i.bak -E "s#^(\tgithub.com/oapi-codegen/oapi-codegen/v2) v[^ ]+#\1 $codegen#" go.mod
if [[ -n "$runtime" ]]; then
    sed -i.bak -E "s#^(\tgithub.com/oapi-codegen/runtime) v[^ ]+#\1 $runtime#" go.mod
fi
rm -f go.mod.bak
sed -i.bak -E "s#^OAPI_CODEGEN_VERSION = \"[^\"]*\"#OAPI_CODEGEN_VERSION = \"$codegen\"#" private/versions.bzl
rm -f private/versions.bzl.bak

# -e: the test packages import generated code that exists only in bazel-out.
bazel run @rules_go//go -- mod tidy -e

grep -E 'oapi-codegen/(v2|runtime) ' go.mod
grep OAPI_CODEGEN_VERSION private/versions.bzl
echo "update_versions: go.mod, go.sum and private/versions.bzl updated. Now update the"
echo "  version strings in README.md, DESIGN.md and tests/assert_generated.sh, then run"
echo "  bazel test //... and the e2e consumer."
