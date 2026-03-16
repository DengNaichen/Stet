#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

enum BrowserAutomationState: Equatable {
    case enabled
    case disabled
}

struct BrowserAutomationTarget: Identifiable, Hashable, Sendable {
    let bundleID: String
    let displayName: String
    let scripts: [String]

    var id: String { bundleID }
}

struct BrowserURLReader {
    struct ScriptProbeResult: Sendable {
        let url: String?
        let permissionDenied: Bool
        let appNotRunning: Bool
        let lastErrorCode: Int?
    }

    static func builtInTargets() -> [BrowserAutomationTarget] {
        [
            BrowserAutomationTarget(
                bundleID: "com.apple.Safari",
                displayName: "Safari",
                scripts: [
                    "tell application id \"com.apple.Safari\" to get URL of front document",
                    "tell application \"Safari\" to get URL of front document",
                ]
            ),
            BrowserAutomationTarget(
                bundleID: "com.apple.SafariTechnologyPreview",
                displayName: "Safari Technology Preview",
                scripts: [
                    "tell application id \"com.apple.SafariTechnologyPreview\" to get URL of front document",
                    "tell application \"Safari Technology Preview\" to get URL of front document",
                ]
            ),
            BrowserAutomationTarget(
                bundleID: "com.google.Chrome",
                displayName: "Google Chrome",
                scripts: [
                    "tell application id \"com.google.Chrome\" to get the URL of active tab of front window",
                    "tell application \"Google Chrome\" to get the URL of active tab of front window",
                ]
            ),
            BrowserAutomationTarget(
                bundleID: "com.microsoft.edgemac",
                displayName: "Microsoft Edge",
                scripts: [
                    "tell application id \"com.microsoft.edgemac\" to get the URL of active tab of front window",
                    "tell application \"Microsoft Edge\" to get the URL of active tab of front window",
                ]
            ),
            BrowserAutomationTarget(
                bundleID: "com.brave.Browser",
                displayName: "Brave",
                scripts: [
                    "tell application id \"com.brave.Browser\" to get the URL of active tab of front window",
                    "tell application \"Brave Browser\" to get the URL of active tab of front window",
                ]
            ),
            BrowserAutomationTarget(
                bundleID: "company.thebrowser.Browser",
                displayName: "Arc",
                scripts: [
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window",
                    "tell application \"Arc\" to get the URL of active tab of front window",
                ]
            ),
        ]
    }

    static func supportedBrowserBundleIDs() -> Set<String> {
        Set(builtInTargets().map(\.bundleID))
    }

    static func automationPermissionStatus(for bundleID: String, askUserIfNeeded: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = descriptor.aeDesc else {
            return OSStatus(errAEEventNotPermitted)
        }

        return AEDeterminePermissionToAutomateTarget(
            aeDesc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEGetData),
            askUserIfNeeded
        )
    }

    static func browserAutomationState(for bundleID: String) -> BrowserAutomationState {
        automationPermissionStatus(for: bundleID, askUserIfNeeded: false) == noErr ? .enabled : .disabled
    }

    static func requestAutomationPermission(for bundleID: String) -> BrowserAutomationState {
        automationPermissionStatus(for: bundleID, askUserIfNeeded: true) == noErr ? .enabled : .disabled
    }

    static func readActiveURL(for bundleID: String) -> String? {
        guard let target = builtInTargets().first(where: { $0.bundleID == bundleID }) else {
            return nil
        }

        let result = runAppleScriptCandidates(target.scripts)
        return result.url
    }

    static func testURLRead(for bundleID: String) -> ScriptProbeResult {
        guard let target = builtInTargets().first(where: { $0.bundleID == bundleID }) else {
            return ScriptProbeResult(url: nil, permissionDenied: false, appNotRunning: false, lastErrorCode: nil)
        }

        return runAppleScriptCandidates(target.scripts)
    }

    private static func runAppleScriptCandidates(_ scripts: [String]) -> ScriptProbeResult {
        var sawPermissionDenied = false
        var sawAppNotRunning = false
        var lastErrorCode: Int?

        for source in scripts {
            var error: NSDictionary?
            let wrapped = """
            with timeout of 1 seconds
            \(source)
            end timeout
            """

            let script = NSAppleScript(source: wrapped)
            let result = script?.executeAndReturnError(&error)

            if let url = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                return ScriptProbeResult(url: url, permissionDenied: false, appNotRunning: false, lastErrorCode: nil)
            }

            let code = error?[NSAppleScript.errorNumber] as? Int
            lastErrorCode = code

            if code == -1743 || code == -10004 {
                sawPermissionDenied = true
            } else if code == -600 {
                sawAppNotRunning = true
            }
        }

        return ScriptProbeResult(
            url: nil,
            permissionDenied: sawPermissionDenied,
            appNotRunning: sawAppNotRunning,
            lastErrorCode: lastErrorCode
        )
    }
}
#endif
