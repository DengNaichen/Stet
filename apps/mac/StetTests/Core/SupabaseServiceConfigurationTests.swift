import Foundation
import Testing

@testable import Stet

@Suite("Supabase Service Configuration", .serialized)
struct SupabaseServiceConfigurationTests {
    @Test func resolvesSupabaseConfigurationFromEnvironment() throws {
        let environment = [
            "SUPABASE_URL": "https://example.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "anon-key-123",
        ]

        let urlString = try #require(
            SupabaseService.Configuration.resolvedValue(
                for: "SUPABASE_URL",
                environment: environment,
                infoDictionary: [:],
                fileManager: .default
            )
        )
        let publishableKey = try #require(
            SupabaseService.Configuration.resolvedValue(
                for: "SUPABASE_PUBLISHABLE_KEY",
                environment: environment,
                infoDictionary: [:],
                fileManager: .default
            )
        )

        let baseURL = try #require(URL(string: urlString))
        let functionsURL = baseURL.appendingPathComponent("functions/v1")

        #expect(urlString == "https://example.supabase.co")
        #expect(publishableKey == "anon-key-123")
        #expect(functionsURL.absoluteString == "https://example.supabase.co/functions/v1")
    }

    @Test func environmentTakesPrecedenceOverInfoDictionaryAndEnvFiles() throws {
        let environment = ["SUPABASE_URL": "https://env.example.supabase.co"]
        let infoDictionary = ["SUPABASE_URL": "https://info.example.supabase.co"]

        let resolved = SupabaseService.Configuration.resolvedValue(
            for: "SUPABASE_URL",
            environment: environment,
            infoDictionary: infoDictionary,
            fileManager: .default
        )

        #expect(resolved == "https://env.example.supabase.co")
    }

    @Test func appBundleExportsSupabaseConfigurationToInfoDictionary() throws {
        let appBundle = Bundle(for: SupabaseService.self)
        let infoDictionary = try #require(appBundle.infoDictionary)

        let url = try #require(
            SupabaseService.Configuration.resolvedValue(
                for: "SUPABASE_URL",
                environment: [:],
                infoDictionary: infoDictionary,
                fileManager: .default
            )
        )
        let key = try #require(
            SupabaseService.Configuration.resolvedValue(
                for: "SUPABASE_PUBLISHABLE_KEY",
                environment: [:],
                infoDictionary: infoDictionary,
                fileManager: .default
            )
        )

        #expect(url == "https://qtffabmkvbkzarwevfrk.supabase.co")
        #expect(key == "sb_publishable_DiDRWukKUQrcdBDUjYmJGw_5N51MiHP")
    }
}
