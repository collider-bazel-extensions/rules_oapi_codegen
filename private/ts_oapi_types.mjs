// ts_oapi_types generator: OpenAPI 3 spec -> one TypeScript module.
//
//   node --preserve-symlinks --preserve-symlinks-main ts_oapi_types.mjs \
//       <node_modules dir> <spec> <out> <spec label for the header>
//
// The module holds openapi-typescript's output (`paths`, `components`,
// `operations`, ...) followed by `operationMap` (operationId -> method and
// path template, as a const) and helper types that index `operations`.
//
// openapi-typescript and its dependencies come from the pinned npm tree
// passed as the first argument (no bare-specifier resolution from this
// file's location), so the script needs nothing from the host.

import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [nodeModules, specPath, outPath, specLabel] = process.argv.slice(2);
if (!nodeModules || !specPath || !outPath || !specLabel) {
    console.error("usage: ts_oapi_types.mjs <node_modules> <spec> <out> <spec label>");
    process.exit(2);
}

const METHODS = ["get", "put", "post", "delete", "options", "head", "patch", "trace"];
const IDENT = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

function fail(msg) {
    console.error(`ts_oapi_types: ${specLabel}: ${msg}`);
    process.exit(1);
}

// Follows a local "#/..." JSON pointer; the bundled document has no
// external $refs left.
function deref(doc, node, where) {
    const seen = new Set();
    while (node && typeof node === "object" && typeof node.$ref === "string") {
        const ref = node.$ref;
        if (!ref.startsWith("#/") || seen.has(ref)) {
            fail(`cannot resolve $ref "${ref}" at ${where}`);
        }
        seen.add(ref);
        node = ref.slice(2).split("/").reduce((cur, part) => {
            const key = part.replace(/~1/g, "/").replace(/~0/g, "~");
            return cur && typeof cur === "object" ? cur[key] : undefined;
        }, doc);
    }
    return node;
}

function operationEntries(doc) {
    const entries = [];
    const seen = new Map();
    for (const [path, rawItem] of Object.entries(doc.paths ?? {})) {
        const item = deref(doc, rawItem, `paths["${path}"]`);
        if (!item || typeof item !== "object") continue;
        for (const method of METHODS) {
            const op = item[method];
            if (!op || typeof op !== "object" || op.operationId === undefined) continue;
            const id = op.operationId;
            if (typeof id !== "string" || id === "") {
                fail(`${method.toUpperCase()} ${path}: operationId must be a non-empty string`);
            }
            if (seen.has(id)) {
                fail(`duplicate operationId "${id}" (${seen.get(id)} and ${method.toUpperCase()} ${path})`);
            }
            seen.set(id, `${method.toUpperCase()} ${path}`);
            entries.push({ id, method, path });
        }
    }
    return entries;
}

function renderOperations(entries) {
    const key = (id) => (IDENT.test(id) ? id : JSON.stringify(id));
    const rows = entries.map(
        (e) => `    ${key(e.id)}: { method: ${JSON.stringify(e.method)}, path: ${JSON.stringify(e.path)} },\n`,
    );
    return `
/**
 * Every operation that has an operationId: its HTTP method (lower case, as
 * in \`paths\`) and its path template. Operations without an operationId
 * are not listed.
 */
export const operationMap = {
${rows.join("")}} as const;

/** An operationId listed in \`operationMap\`. */
export type OperationId = keyof typeof operationMap;
/** The operation's HTTP method, lower case. */
export type OperationMethod<Id extends OperationId> = (typeof operationMap)[Id]["method"];
/** The operation's path template, a key of \`paths\`. */
export type OperationPath<Id extends OperationId> = (typeof operationMap)[Id]["path"];
/** All of the operation's parameters (\`path\`, \`query\`, \`header\`, \`cookie\`). */
export type OperationParameters<Id extends OperationId> = operations[Id]["parameters"];
/** Path parameters; \`undefined\` when there are none. */
export type OperationPathParams<Id extends OperationId> = operations[Id]["parameters"]["path"];
/** Query parameters; \`undefined\` when there are none. */
export type OperationQueryParams<Id extends OperationId> = operations[Id]["parameters"]["query"];
/** Header parameters; \`undefined\` when there are none. */
export type OperationHeaderParams<Id extends OperationId> = operations[Id]["parameters"]["header"];
type ContentOf<T> = T extends { content: infer C } ? C[keyof C] : never;
/** The request body (union over its media types); \`never\` when there is none. */
export type OperationRequestBody<Id extends OperationId> = ContentOf<NonNullable<operations[Id]["requestBody"]>>;
/** The operation's responses, keyed by status code (or \`default\`). */
export type OperationResponses<Id extends OperationId> = operations[Id]["responses"];
/** One response's body (union over its media types); \`never\` when it has none. */
export type OperationResponseBody<
    Id extends OperationId,
    Status extends keyof OperationResponses<Id>,
> = ContentOf<OperationResponses<Id>[Status]>;
`;
}

async function main() {
    const oatsDir = join(resolve(nodeModules), "openapi-typescript");
    const load = (file) => import(pathToFileURL(join(oatsDir, file)).href);
    // Resolves openapi-typescript's own dependencies from its directory.
    const req = createRequire(join(oatsDir, "package.json"));
    const oatsPkg = req("./package.json");
    const oats = await load("dist/index.mjs");
    const { validateAndBundle } = await load("dist/lib/redoc.mjs");
    // CommonJS only, so this is the instance openapi-typescript imports.
    const { createConfig } = req("@redocly/openapi-core");

    // openapi-typescript's own default config: the "minimal" ruleset, with
    // duplicate operationIds as an error.
    const redocly = await createConfig(
        { rules: { "operation-operationId-unique": { severity: "error" } } },
        { extends: ["minimal"] },
    );
    const specURL = pathToFileURL(resolve(specPath));
    let doc, ast;
    try {
        doc = await validateAndBundle(specURL, { redoc: redocly, cwd: specURL, silent: true });
        ast = await oats.default(doc, { redocly, silent: true });
    } catch (err) {
        fail(err && err.message ? err.message : String(err));
    }
    const entries = operationEntries(doc);

    const header =
        `// Code generated by rules_oapi_codegen ts_oapi_types (openapi-typescript ` +
        `${oatsPkg.version}) from ${specLabel}. DO NOT EDIT.\n\n`;
    writeFileSync(outPath, header + oats.COMMENT_HEADER + oats.astToString(ast) + renderOperations(entries));
}

main().catch((err) => fail(err && err.stack ? err.stack : String(err)));
