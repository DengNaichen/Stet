#if os(macOS)
import Testing

@testable import Stet

@MainActor
@Suite("AppBranch", .tags(.appBranch))
struct AppBranchTests {}
#endif
