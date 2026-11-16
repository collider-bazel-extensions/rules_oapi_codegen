#!/usr/bin/env bash
# Usage: golden_test.sh <generated.ts> <golden>
# The generated module must match the checked-in golden file byte for byte.
set -euo pipefail
if ! diff -u "$2" "$1"; then
    echo "FAIL: $1 differs from $2." >&2
    echo "  If the change is intended: bazel build //tests/ts:petstore &&" >&2
    echo "  cp bazel-bin/tests/ts/petstore.ts tests/ts/petstore.ts.golden" >&2
    exit 1
fi
grep -Eq '^// Code generated .* DO NOT EDIT\.$' "$1" \
    || { echo "FAIL: $1 lacks a '// Code generated ... DO NOT EDIT.' line" >&2; exit 1; }
echo "PASS: $1 matches $2"
