import Foundation
import Testing

@testable import Stet

@Suite("Audio Post Processing Result")
struct AudioPostProcessingResultTests {
    @Test func passthroughCreatesNonDiscardResult() {
        let url = URL(fileURLWithPath: "/tmp/test.wav")
        let result = AudioPostProcessingResult.passthrough(url: url, duration: 1.5)
        
        #expect(result.url == url)
        #expect(result.duration == 1.5)
        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(result.cleanupURLs == [url])
    }
    
    @Test func discardCreatesDiscardResult() {
        let url = URL(fileURLWithPath: "/tmp/test.wav")
        let result = AudioPostProcessingResult.discard(url: url, duration: 2.0)
        
        #expect(result.url == url)
        #expect(result.duration == 2.0)
        #expect(result.shouldDiscardAsNoSpeech)
        #expect(result.cleanupURLs == [url])
    }
    
    @Test func rewrittenCreatesResultWithBothURLs() {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.wav")
        let rewrittenURL = URL(fileURLWithPath: "/tmp/rewritten.wav")
        let result = AudioPostProcessingResult.rewritten(
            sourceURL: sourceURL,
            rewrittenURL: rewrittenURL,
            duration: 3.0
        )
        
        #expect(result.url == rewrittenURL)
        #expect(result.duration == 3.0)
        #expect(!result.shouldDiscardAsNoSpeech)
        #expect(Set(result.cleanupURLs) == Set([sourceURL, rewrittenURL]))
    }
}
