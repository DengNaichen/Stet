export function log(
    level: "info" | "warn" | "error",
    event: string,
    requestId: string,
    metadata: Record<string, unknown> = {}
) {
    const payload = {
        level,
        event,
        request_id: requestId,
        timestamp: new Date().toISOString(),
        ...metadata
    };

    console[level](JSON.stringify(payload));
}