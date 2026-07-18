#if os(macOS)
    import Darwin
    import Foundation
    import MCP
    import Testing

    @testable import Stet

    @Suite("Stet MCP HTTP Server")
    struct StetMCPHTTPServerTests {
        @Test func bindsAndStopsNormally() async throws {
            let server = makeHTTPServer(port: 0)
            let runTask = Task { try await server.run() }

            let listening = await TestSupport.eventuallyAsync {
                await server.isListening()
            }
            guard listening else {
                runTask.cancel()
                _ = try? await runTask.value
                Issue.record("MCP HTTP server did not begin listening")
                return
            }

            await server.stop()
            try await runTask.value
            #expect(!(await server.isListening()))
        }

        @Test func occupiedPortFailsToBind() async throws {
            let reservation = try LocalPortReservation()
            defer { reservation.close() }
            let server = makeHTTPServer(port: reservation.port)

            do {
                try await server.run()
                Issue.record("Expected binding an occupied port to fail")
            } catch {
                #expect(!(await server.isListening()))
            }
        }

        private func makeHTTPServer(port: Int) -> StetMCPHTTPServer {
            StetMCPHTTPServer(
                configuration: .init(host: "127.0.0.1", port: port, endpoint: "/mcp")
            ) { _ in
                .ok()
            }
        }
    }

    private nonisolated final class LocalPortReservation: @unchecked Sendable {
        let port: Int
        private let lock = NSLock()
        private var fileDescriptor: Int32?

        init() throws {
            let fileDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard fileDescriptor >= 0 else {
                throw POSIXError(.ENFILE)
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        fileDescriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
            guard bindResult == 0, Darwin.listen(fileDescriptor, 1) == 0 else {
                Darwin.close(fileDescriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
            }

            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(fileDescriptor, $0, &addressLength)
                }
            }
            guard nameResult == 0 else {
                Darwin.close(fileDescriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
            }

            self.port = Int(UInt16(bigEndian: address.sin_port))
            self.fileDescriptor = fileDescriptor
        }

        func close() {
            let fileDescriptor = lock.withLock {
                defer { self.fileDescriptor = nil }
                return self.fileDescriptor
            }
            if let fileDescriptor {
                Darwin.close(fileDescriptor)
            }
        }

        deinit {
            close()
        }
    }
#endif
