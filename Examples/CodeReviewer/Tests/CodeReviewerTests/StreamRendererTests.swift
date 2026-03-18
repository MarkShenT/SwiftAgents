import Testing
@testable import CodeReviewer

@Suite("StreamRenderer")
struct StreamRendererTests {

    @Test("formats security prefix with red color")
    func securityPrefix() {
        let result = StreamRenderer.format("hello", agent: .security)
        #expect(result.contains("[Security]"))
        #expect(result.contains("hello"))
        #expect(result.contains(StreamRenderer.ANSICode.red))
    }

    @Test("formats performance prefix with yellow color")
    func performancePrefix() {
        let result = StreamRenderer.format("world", agent: .performance)
        #expect(result.contains("[Performance]"))
        #expect(result.contains(StreamRenderer.ANSICode.yellow))
    }

    @Test("formats style prefix with blue color")
    func stylePrefix() {
        let result = StreamRenderer.format("test", agent: .style)
        #expect(result.contains("[Style]"))
        #expect(result.contains(StreamRenderer.ANSICode.blue))
    }

    @Test("formats synthesizer prefix with green color")
    func synthesizerPrefix() {
        let result = StreamRenderer.format("summary", agent: .synthesizer)
        #expect(result.contains("[Summary]"))
        #expect(result.contains(StreamRenderer.ANSICode.green))
    }
}
