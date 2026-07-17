import Foundation

extension ProcessInfo {
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }

    var isRunningAppleIntelligenceRewriteProbe: Bool {
        arguments.contains("--run-ai-rewrite-probe")
    }
}
