#!/usr/bin/env bash
# A Go-only build must not fetch ts_oapi_types' Node.js or npm repositories.
#
#   e2e/consumer/go_only_check.sh [<fresh output base>]
#
# Builds //api (go_oapi_client only) in a fresh output base and fails if any
# rules_oapi_codegen ts_deps repository (oapi_ts_node_*, oapi_ts_npm) was
# fetched. Then builds //ts:api as a control: the same check must see them,
# or it isn't checking anything.
set -euo pipefail
cd "$(dirname "$0")"
ob="${1:-$(mktemp -d)}"
bz() { bazel --output_base="$ob" "$@"; }
trap 'bz shutdown >/dev/null 2>&1 || true' EXIT

ts_repos() { ls -a "$ob/external" 2>/dev/null | grep -E 'oapi_ts_(node|npm)' || true; }

bz build //api/...
fetched="$(ts_repos)"
if [[ -n "$fetched" ]]; then
    echo "FAIL: a Go-only build fetched ts_oapi_types repositories:" >&2
    echo "$fetched" >&2
    exit 1
fi
echo "PASS: building //api/... fetched no oapi_ts_node_* / oapi_ts_npm repository"

bz build //ts:api
fetched="$(ts_repos)"
if ! grep -q oapi_ts_npm <<<"$fetched" || ! grep -q oapi_ts_node_ <<<"$fetched"; then
    echo "FAIL: control: building //ts:api did not fetch the Node.js and npm repositories" >&2
    exit 1
fi
echo "PASS (control): building //ts:api fetched:"
echo "$fetched" | sed 's/^/  /'
