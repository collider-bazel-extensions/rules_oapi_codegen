#!/usr/bin/env bash
# Usage: typecheck_test.sh <node> <tsc.js> <usage.ts> <generated.ts>...
# 1. tsc --noEmit --strict (plus the stricter flags TS servers tend to turn
#    on) over the generated module(s) and usage.ts, which asserts the
#    generated types with type-level equality checks.
# 2. Node runs usage.ts (type stripping) to check operationMap at runtime.
# Both run the pinned Node and the pinned TypeScript from the npm lock.
set -euo pipefail
node="$1"; tsc="$2"; usage="$3"; shift 3

"$node" --preserve-symlinks --preserve-symlinks-main "$tsc" --version
"$node" --preserve-symlinks --preserve-symlinks-main "$tsc" \
    --noEmit --strict \
    --target es2022 --lib es2022 --module esnext --moduleResolution bundler \
    --allowImportingTsExtensions --verbatimModuleSyntax --isolatedModules \
    --erasableSyntaxOnly --exactOptionalPropertyTypes --noUncheckedIndexedAccess \
    --noImplicitReturns --noFallthroughCasesInSwitch --noPropertyAccessFromIndexSignature \
    --forceConsistentCasingInFileNames \
    "$usage" "$@"
echo "PASS: tsc --noEmit --strict"

"$node" --preserve-symlinks --preserve-symlinks-main --no-warnings "$usage"
echo "PASS: operationMap at runtime (node $("$node" --version))"
