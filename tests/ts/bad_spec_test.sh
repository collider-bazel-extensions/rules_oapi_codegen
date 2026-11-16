#!/usr/bin/env bash
# Usage: bad_spec_test.sh <node> <ts_oapi_types.mjs> <openapi-typescript/package.json> \
#            (<spec> <expected stderr substring>)...
# Runs the ts_oapi_types generator (same argv as the rule's action) over
# each invalid spec and checks it exits non-zero, writes no output, and
# prints a "ts_oapi_types: <spec>: <reason>" error naming the problem.
set -euo pipefail

node="$1"; script="$2"; pkg="$3"; shift 3
node_modules="$(dirname "$(dirname "$pkg")")"

fail() { echo "FAIL: $*" >&2; exit 1; }

while (($#)); do
    spec="$1"; want="$2"; shift 2
    out="$TEST_TMPDIR/$(basename "$spec").ts"
    rc=0
    FORCE_COLOR=0 NO_COLOR=1 "$node" --preserve-symlinks --preserve-symlinks-main \
        "$script" "$node_modules" "$spec" "$out" "$spec" 2>"$TEST_TMPDIR/err" || rc=$?
    cat "$TEST_TMPDIR/err"
    ((rc != 0)) || fail "$spec: generator succeeded, want an error"
    [[ ! -e "$out" ]] || fail "$spec: generator wrote $out despite failing"
    grep -qF "ts_oapi_types: $spec: $want" "$TEST_TMPDIR/err" \
        || fail "$spec: stderr lacks 'ts_oapi_types: $spec: $want'"
    echo "PASS: $spec -> $want"
done
