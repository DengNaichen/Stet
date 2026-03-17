export class ApiError extends Error {
    status: number;
    code: string;
    retryAfterSeconds?: number;

    constructor(status: number, code: string, message: string, retryAfterSeconds?: number) {
        super(message)
        this.status = status
        this.code = code;
        this.retryAfterSeconds = retryAfterSeconds
    }
}