// Compiled with the generated petstore.ts by `tsc --noEmit --strict` (plus
// stricter flags; see typecheck_test.sh), then run by Node (type stripping)
// to check operationMap at runtime.
import {
    operationMap,
    type OperationId,
    type OperationHeaderParams,
    type OperationMethod,
    type OperationPath,
    type OperationPathParams,
    type OperationQueryParams,
    type OperationRequestBody,
    type OperationResponseBody,
    type OperationResponses,
    type components,
    type operations,
    type paths,
} from "./petstore.ts";

type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false;
function expectType<T extends true>(): T | undefined {
    return undefined;
}

type Pet = components["schemas"]["Pet"];
type NewPet = components["schemas"]["NewPet"];
type ApiError = components["schemas"]["Error"];

// operationMap: every operationId, nothing else (/health has none).
expectType<Equal<OperationId, "listPets" | "createPet" | "getPet" | "deletePet" | "update-pet">>();
expectType<Equal<OperationId, keyof operations>>();
expectType<Equal<OperationMethod<"update-pet">, "patch">>();
expectType<Equal<OperationPath<"getPet">, "/pets/{petId}">>();
expectType<Equal<(typeof operationMap)["createPet"], { readonly method: "post"; readonly path: "/pets" }>>();

// Paths in the map are keys of `paths`, and method + path index the same
// operation type openapi-typescript put there.
expectType<Equal<paths[OperationPath<"getPet">][OperationMethod<"getPet">], operations["getPet"]>>();

// Parameters: path (from a path-level $ref), query, header ($ref).
expectType<Equal<OperationPathParams<"getPet">, { petId: number }>>();
expectType<Equal<OperationPathParams<"listPets">, undefined>>();
expectType<Equal<OperationQueryParams<"listPets">, { limit?: number; tag?: string } | undefined>>();
expectType<Equal<OperationHeaderParams<"listPets">, { "X-Request-Id"?: string } | undefined>>();

// Request bodies: required, optional, none.
expectType<Equal<OperationRequestBody<"createPet">, NewPet>>();
expectType<Equal<OperationRequestBody<"update-pet">, components["schemas"]["PetPatch"]>>();
expectType<Equal<OperationRequestBody<"getPet">, never>>();

// Responses: several codes, a $ref'd response, default, no content.
expectType<Equal<keyof OperationResponses<"createPet">, 201 | 400 | 409>>();
expectType<Equal<keyof OperationResponses<"listPets">, 200 | "default">>();
expectType<Equal<OperationResponseBody<"createPet", 201>, Pet>>();
expectType<Equal<OperationResponseBody<"createPet", 400>, ApiError>>();
expectType<Equal<OperationResponseBody<"listPets", 200>, Pet[]>>();
expectType<Equal<OperationResponseBody<"listPets", "default">, ApiError>>();
expectType<Equal<OperationResponseBody<"deletePet", 204>, never>>();

// $ref'd components compose: Pet = NewPet & { id }.
const pet: Pet = { id: 1, name: "Rex", status: "available" };
// @ts-expect-error: status is an enum
const badPet: Pet = { id: 1, name: "Rex", status: "lost" };
// @ts-expect-error: not an operationId
type NoSuchOp = OperationPathParams<"nope">;
// @ts-expect-error: getPet has no 201 response
type NoSuchStatus = OperationResponseBody<"getPet", 201>;

// A typed route table built from the map, the way a REST gateway would.
type Handler<Id extends OperationId> = (
    params: OperationPathParams<Id>,
    body: OperationRequestBody<Id>,
) => OperationResponseBody<Id, keyof OperationResponses<Id>>;
const getPet: Handler<"getPet"> = ({ petId }) => ({ ...pet, id: petId });

function route(method: string, path: string): OperationId | undefined {
    for (const id of Object.keys(operationMap) as OperationId[]) {
        const op = operationMap[id];
        if (op.method === method && op.path === path) return id;
    }
    return undefined;
}

const checks: [string, unknown, unknown][] = [
    ["route(get, /pets/{petId})", route("get", "/pets/{petId}"), "getPet"],
    ["route(patch, /pets/{petId})", route("patch", "/pets/{petId}"), "update-pet"],
    ["route(get, /health)", route("get", "/health"), undefined],
    ["operation count", Object.keys(operationMap).length, 5],
    ["getPet handler", getPet({ petId: 7 }, undefined as never), { ...pet, id: 7 }],
];
for (const [what, got, want] of checks) {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
        throw new Error(`${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
    }
}
void badPet;
