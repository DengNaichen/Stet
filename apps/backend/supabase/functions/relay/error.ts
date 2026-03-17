import type { ContentfulStatusCode } from "hono/utils/http-status";

export class ApiError extends Error {
    status: ContentfulStatusCode;
    code: string;
    retryAfterSeconds?: number;

    constructor(status: ContentfulStatusCode, code: string, message: string, retryAfterSeconds?: number) {
        super(message)
        this.status = status
        this.code = code;
        this.retryAfterSeconds = retryAfterSeconds
    }
}
