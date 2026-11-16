#!/usr/bin/env bash
# Maintainer-time script: regenerate private/npm/package-lock.json, the npm
# tree ts_oapi_types runs (openapi-typescript and its dependencies, plus
# typescript, its peer dependency, which the tests also use for tsc).
#
#   tools/update_npm_lock.sh                      # re-resolve the current pins
#   tools/update_npm_lock.sh <openapi-typescript version> [<typescript version>]
#   tools/update_npm_lock.sh 7.13.0 5.9.3
#
# Needs npm on the host (only here; builds never run it). Resolves against
# registry.npmjs.org, runs no install scripts, and writes lockfileVersion 3,
# which the npm_repo repository rule (private/ts_deps.bzl) reads: every
# packages["node_modules/..."] entry is downloaded from its `resolved` URL
# and checked against its sha512 `integrity`.
# Afterwards: rebuild the golden file (see tests/ts/golden_test.sh), update
# the version strings in README.md, DESIGN.md and CLAUDE.md, and run
# `bazel test //...` plus the e2e consumer.
set -euo pipefail

cd "$(dirname "$0")/../private/npm"

oats="${1:-}"
ts="${2:-}"
for v in ${oats:+"$oats"} ${ts:+"$ts"}; do
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "update_npm_lock: bad version '$v' (want X.Y.Z)" >&2; exit 1; }
done
if [[ -n "$oats" ]]; then
    sed -i.bak -E "s#(\"openapi-typescript\": )\"[^\"]*\"#\1\"$oats\"#" package.json
fi
if [[ -n "$ts" ]]; then
    sed -i.bak -E "s#(\"typescript\": )\"[^\"]*\"#\1\"$ts\"#" package.json
fi
rm -f package.json.bak

rm -f package-lock.json
npm install --package-lock-only --lockfile-version 3 --ignore-scripts \
    --no-audit --no-fund --registry https://registry.npmjs.org/

# The tree is shared by every exec platform: refuse platform-specific
# packages, and anything not pinned by a sha512 integrity.
python3 -I - package-lock.json <<'PY'
import json, sys
lock = json.load(open(sys.argv[1]))
bad = []
for path, pkg in lock["packages"].items():
    if not path:
        continue
    if "os" in pkg or "cpu" in pkg:
        bad.append(f"{path}: platform-specific (os/cpu)")
    if pkg.get("link") or not pkg.get("integrity", "").startswith("sha512-"):
        bad.append(f"{path}: not a registry tarball with sha512 integrity")
    if not pkg.get("resolved", "").startswith("https://registry.npmjs.org/"):
        bad.append(f"{path}: resolved outside registry.npmjs.org")
if bad:
    sys.exit("update_npm_lock: unsupported packages:\n  " + "\n  ".join(bad))
print(f"update_npm_lock: {len(lock['packages']) - 1} packages")
for name in ("openapi-typescript", "typescript"):
    print(f"  {name} {lock['packages']['node_modules/' + name]['version']}")
PY
