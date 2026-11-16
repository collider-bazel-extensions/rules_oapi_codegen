// A REST gateway's view of the spec: route by method and path through
// operationMap, typed by the generated helper types.
import {
    operationMap,
    type OperationId,
    type OperationResponseBody,
    type components,
} from "./api";

type Health = components["schemas"]["Health"];

export function route(method: string, path: string): OperationId | undefined {
    for (const id of Object.keys(operationMap) as OperationId[]) {
        const op = operationMap[id];
        if (op.method === method && op.path === path) return id;
    }
    return undefined;
}

export function getHealth(): OperationResponseBody<"getHealth", 200> {
    const body: Health = { status: "ok", checkedAt: "2026-01-01T00:00:00Z" };
    return body;
}
