import SwiftUI

// Shared UI components for SwiftUI views across the app.
// These are intentionally lightweight and platform-agnostic.

// MARK: - Message Banner

enum MessageBannerRole {
    case info, success, warning, error

    var tint: Color {
        switch self {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct MessageBanner: View {
    let text: String
    let role: MessageBannerRole
    var strokeOpacity: Double = 0.18
    var fillOpacity: Double = 0.08
    var icon: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(role.tint)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(role.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(role.tint.opacity(fillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(role.tint.opacity(strokeOpacity), lineWidth: 1)
        )
    }
}

// MARK: - Labeled Fields

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct LabeledTextField<F: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<F?>.Binding?
    var focusEquals: F?

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focused: FocusState<F?>.Binding? = nil,
        focusEquals: F? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.focused = focused
        self.focusEquals = focusEquals
    }

    var body: some View {
        LabeledField(title: title) {
            if let focused, let focusEquals {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused, equals: focusEquals)
            } else {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct LabeledSecureField<F: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<F?>.Binding?
    var focusEquals: F?

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        focused: FocusState<F?>.Binding? = nil,
        focusEquals: F? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.focused = focused
        self.focusEquals = focusEquals
    }

    var body: some View {
        LabeledField(title: title) {
            if let focused, let focusEquals {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused(focused, equals: focusEquals)
            } else {
                SecureField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// MARK: - Bullet Row

struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@ViewBuilder
func bulletRow(_ text: String) -> some View {
    BulletRow(text: text)
}

// MARK: - App Form Wrapper

struct AppForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
    }
}

// MARK: - Async Button

struct AsyncButton<Label: View>: View {
    let action: () async -> Void
    @ViewBuilder var label: () -> Label
    @State private var running = false

    var body: some View {
        Button {
            guard !running else { return }
            running = true
            Task {
                await action()
                running = false
            }
        } label: {
            label()
        }
        .disabled(running)
    }
}
