import Foundation
internal import Auth

extension Provider {
    var displayName: String {
        switch self {
        case .google:
            return "Google"
        case .github:
            return "GitHub"
        default:
            return rawValue.capitalized
        }
    }

    var oauthScopes: String? {
        switch self {
        case .google:
            return "email profile"
        case .github:
            return "read:user user:email"
        default:
            return nil
        }
    }
}
