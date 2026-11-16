#!/usr/bin/env bash
# The commit's release archive (git archive honours .gitattributes
# export-ignore, as GitHub's tag tarballs do) must load for a consumer:
# the export-ignored dirs are absent and `bazel query @<module>//...` works.
# The consumer pins the module's non-dev, non-BCR deps with the same
# overrides as its MODULE.bazel (overrides only apply in the root).
# It then builds a ts_oapi_types target, so the archive carries everything
# that rule fetches and runs.
# Usage: .github/consumer/check.sh <scratch dir>
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$1"
module="$(sed -n 's/^    name = "\(.*\)",$/\1/p' "$repo/MODULE.bazel" | head -1)"
src="$work/$module"
rm -rf "$work"; mkdir -p "$src" "$work/consumer"
git -C "$repo" archive HEAD | tar -x -C "$src"
for d in $(sed -n 's#^\([^ #]*\)/ export-ignore$#\1#p' "$repo/.gitattributes"); do
    if [[ -e "$src/$d" ]]; then echo "FAIL: archive contains $d/" >&2; exit 1; fi
done
overrides="$(python3 -I - "$src/MODULE.bazel" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
deps = {m.group(1) for m in re.finditer(r'bazel_dep\(\s*name\s*=\s*"([^"]+)"([^)]*)\)', s)
        if "dev_dependency" not in m.group(2)}
for m in re.finditer(r'(\w+_override)\((.*?)\n\)', s, re.S):
    name = re.search(r'module_name\s*=\s*"([^"]+)"', m.group(2))
    if name and name.group(1) in deps:
        print(m.group(0))
        dep = re.search(r'bazel_dep\(\s*name\s*=\s*"%s"[^)]*\)' % re.escape(name.group(1)), s)
        print(dep.group(0))
PY
)"
if [[ -f "$repo/.bazelversion" ]]; then cp "$repo/.bazelversion" "$work/consumer/"; fi
touch "$work/consumer/BUILD.bazel"
cat > "$work/consumer/MODULE.bazel" <<MOD
module(name = "consumer")
bazel_dep(name = "$module")
local_path_override(module_name = "$module", path = "$src")
$overrides
MOD
cd "$work/consumer"
bazel query "@$module//..." >/dev/null
echo "PASS: @$module//... loads from the archive"

# ts_oapi_types from the archive: its Node.js and npm repositories resolve
# (private/npm/package-lock.json ships), and the action runs.
cat > openapi.yaml <<'YAML'
openapi: 3.0.3
info: {title: Archive check, version: 1.0.0}
paths:
  /things/{id}:
    get:
      operationId: getThing
      parameters:
        - {name: id, in: path, required: true, schema: {type: string}}
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Thing"}
components:
  schemas:
    Thing:
      type: object
      required: [id]
      properties: {id: {type: string}}
YAML
cat > BUILD.bazel <<BUILD
load("@$module//:defs.bzl", "ts_oapi_types")

ts_oapi_types(name = "api", spec = "openapi.yaml")
BUILD
bazel build //:api
grep -q 'getThing: { method: "get", path: "/things/{id}" },' bazel-bin/api.ts
grep -q '^export interface operations {' bazel-bin/api.ts
echo "PASS: ts_oapi_types builds from the archive"
