import Foundation

#if DEBUG && os(macOS)
    import AppKit

    enum AppleIntelligenceRewriteProbe {
        private struct ProbeCase: Sendable {
            let label: String
            let input: String
        }

        static func runAndTerminate() {
            Task {
                await run()
                NSApplication.shared.terminate(nil)
            }
        }

        private static func run() async {
            print("Apple Intelligence rewrite probe")
            print("Availability: \(AppleIntelligenceRewriteService.availabilityDescription)")

            guard AppleIntelligenceRewriteService.isAvailable else {
                return
            }

            let service = AppleIntelligenceRewriteService()
            let preferredSpellings = ["PR", "SwiftData", "Cloudflare Worker"]
            let cases: [ProbeCase] = [
                ProbeCase(
                    label: "数据库迁移",
                    input: "呃你把那个数据库前移脚本先跑一下，然后再看一下 schema 有没有问题。"
                ),
                ProbeCase(
                    label: "提交 PR",
                    input: "我待会儿把这个改动提一个皮阿尔，你帮我 review 一下。"
                ),
                ProbeCase(
                    label: "SwiftData",
                    input: "这个睡服大他模型里面的字段要改一下，不然 migration 会失败。"
                ),
                ProbeCase(
                    label: "权限弹窗",
                    input: "用户第一次启动的时候会看到全线弹窗，我们要把文案写清楚。"
                ),
                ProbeCase(
                    label: "转写结果",
                    input: "这个专写结果已经出来了，但是后面的重写步骤没有跑。"
                ),
                ProbeCase(
                    label: "Cloudflare Worker",
                    input: "这个 cloud flare 沃克尔里面的环境变量没配，所以请求失败了。"
                ),
            ]

            for testCase in cases {
                let request = TextRewriteRequest.cleanup(
                    testCase.input,
                    audience: .human,
                    preferredSpellings: preferredSpellings,
                    languageCode: "zh"
                )

                do {
                    let result = try await service.rewriteWithDiagnostic(request)
                    print("")
                    print("=== \(testCase.label) ===")
                    print("Input: \(testCase.input)")
                    print("Reason: \(result.reason)")
                    print("Text: \(result.text)")
                } catch {
                    print("")
                    print("=== \(testCase.label) ===")
                    print("Input: \(testCase.input)")
                    print("Error: \(error.localizedDescription)")
                }
            }
        }
    }
#endif
