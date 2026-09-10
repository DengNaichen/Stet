import Foundation

/// Owns retry timing and attempt accounting for cloud rewrite adapters.
/// Provider adapters only decide whether their typed error is retryable.
enum CloudRewriteRetryExecutor {
    static func execute<Value, Failure: Error>(
        attempts: Int,
        shouldRetry: (Failure) -> Bool,
        operation: () async throws -> Value
    ) async throws -> Value {
        precondition(attempts > 0)

        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch let failure as Failure {
                guard shouldRetry(failure), attempt < attempts else {
                    throw failure
                }
                try await backoff(for: attempt)
            } catch {
                guard attempt < attempts else {
                    throw error
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        preconditionFailure("Retry executor exhausted without returning or throwing")
    }

    private static func backoff(for attempt: Int) async throws {
        let delay = pow(2.0, Double(attempt))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
