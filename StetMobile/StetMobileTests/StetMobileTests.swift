//
//  StetMobileTests.swift
//  StetMobileTests
//
//  Created by Naicheng Deng on 2026-04-30.
//

import Foundation
import Testing
import StetCore
@testable import StetMobile

struct StetMobileTests {
    @MainActor
    @Test func dictionaryViewModelLoadsAddsAndRemovesEntries() {
        let defaults = UserDefaults(suiteName: "StetMobileTests.Dictionary.\(UUID().uuidString)")!
        let model = DictionaryModel(
            defaults: defaults,
            entriesKey: "dictionary.entries.\(UUID().uuidString)",
            enabledKey: "dictionary.enabled.\(UUID().uuidString)"
        )
        let subject = DictionaryViewModel(model: model)

        subject.load()
        #expect(subject.allWords.isEmpty)

        subject.draft = "Cursor, OpenAI, cursor"
        subject.addDraftEntries()
        #expect(subject.allWords == ["Cursor", "OpenAI"])

        subject.removeWord("openai")
        #expect(subject.allWords == ["Cursor"])
    }
}
