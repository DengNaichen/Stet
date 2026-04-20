import Foundation

enum StetLinks {
    /// The main website URL
    static let home = URL(string: "https://www.stet.me")!

    /// Stripe top-up/checkout URL
    // static let topUp = URL(string: "https://buy.stripe.com/test_bJebJ0crTf7c1pMaUH9oc00")!

    /// Default Stripe Price ID for top-ups
    static let defaultPriceID = "price_1TO8GCBs8GxbN43XxLy3dGOL"

    /// Community and social links
    static let discord = URL(string: "https://discord.gg/BKcYVAEK")!
    static let x = URL(string: "https://x.com/Danielvrnh")!
    static let github = URL(string: "https://github.com/DengNaichen/Stet")!
}
