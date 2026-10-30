#!/usr/bin/env bash
# Usage: version_sync_test.sh <go.mod> <versions.bzl>
# OAPI_CODEGEN_VERSION (written into generated headers) must equal the
# oapi-codegen version go.mod pins, or generated headers lie about which
# version produced them.
set -euo pipefail

mod=$(sed -nE 's#^\tgithub.com/oapi-codegen/oapi-codegen/v2 (v[^ ]+).*#\1#p' "$1")
bzl=$(sed -nE 's#^OAPI_CODEGEN_VERSION = "([^"]+)"#\1#p' "$2")
[[ -n "$mod" && -n "$bzl" ]] || { echo "FAIL: version not found (go.mod='$mod', versions.bzl='$bzl')" >&2; exit 1; }
[[ "$mod" == "$bzl" ]] || {
    echo "FAIL: go.mod pins oapi-codegen $mod but private/versions.bzl says $bzl." >&2
    echo "Run tools/update_versions.sh $mod" >&2
    exit 1
}
echo "PASS: oapi-codegen $mod"
