#if os(macOS)
import SwiftUI
import WebKit

// MARK: - Components

struct OnboardingChoiceCard: View {
    let title: String
    let details: [String]
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(details, id: \.self) { detail in
                    BulletRow(text: detail)
                }
            }

            Spacer(minLength: 0)

            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct StatusChecklistRow: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)

            Text(title)
        }
    }
}

struct PermissionGateRow<Actions: View>: View {
    let title: String
    let description: String
    let statusText: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MacSettingsStatusBadge(text: statusText, tint: tint)
            }

            actions()
        }
    }
}

// MARK: - WebView & Styles

struct OnboardingWebView: NSViewRepresentable {
    let step: MacOnboardingStep

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // You can load local HTML files here or point to a remote URL.
        // For demonstration, generating a generic colored gradient page matching the step.
        let colors: [MacOnboardingStep: String] = [
            .welcome: "linear-gradient(135deg, #a18cd1 0%, #fbc2eb 100%)",
            .mode: "linear-gradient(135deg, #84fab0 0%, #8fd3f4 100%)",
            .apiKey: "linear-gradient(135deg, #fccb90 0%, #d57eeb 100%)",
            .login: "linear-gradient(135deg, #e0c3fc 0%, #8ec5fc 100%)",
            .permissions: "linear-gradient(135deg, #f093fb 0%, #f5576c 100%)",
            .shortcut: "linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)",
            .firstSuccess: "linear-gradient(135deg, #43e97b 0%, #38f9d7 100%)",
            .done: "linear-gradient(135deg, #fa709a 0%, #fee140 100%)"
        ]
        
        let background = colors[step] ?? "black"
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    margin: 0; 
                    padding: 0; 
                    display: flex; 
                    flex-direction: column;
                    align-items: center; 
                    justify-content: center; 
                    height: 100vh; 
                    background: \(background);
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    color: white;
                    text-align: center;
                }
                h1 { font-size: 3rem; margin-bottom: 0.5rem; text-shadow: 0 2px 10px rgba(0,0,0,0.1); font-weight: 600; letter-spacing: -0.02em; }
                p { font-size: 1.2rem; opacity: 0.9; margin: 0 2rem; line-height: 1.5; }
            </style>
        </head>
        <body>
            <h1>Step \(step.progressIndex)</h1>
            <p>This is a placeholder WebView. You can replace this with your own animated visuals or colors.</p>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

struct CleanGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let label = configuration.label as? Text {
                label.font(.headline.weight(.semibold))
            }
            configuration.content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

#endif
