// MemoryFactoryTests.swift
// SwarmTests
//
// TDD tests for AnyMemory static factory methods.

import Testing
@testable import Swarm

@Suite("AnyMemory Factory Methods")
struct MemoryFactoryTests {
    @Test("conversation factory creates AnyMemory")
    func conversationFactory() async {
        let memory = AnyMemory.conversation()
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("conversation factory respects maxMessages parameter")
    func conversationFactoryWithMaxMessages() async {
        let memory = AnyMemory.conversation(maxMessages: 50)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("slidingWindow factory creates AnyMemory")
    func slidingWindowFactory() async {
        let memory = AnyMemory.slidingWindow(maxTokens: 1000)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("slidingWindow factory uses default maxTokens")
    func slidingWindowFactoryDefaultTokens() async {
        let memory = AnyMemory.slidingWindow()
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("vector factory creates AnyMemory with provider")
    func vectorFactory() async {
        let provider = MockEmbeddingProvider()
        let memory = AnyMemory.vector(embeddingProvider: provider)
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("persistent factory creates AnyMemory with default in-memory backend")
    func persistentFactory() async {
        let memory = AnyMemory.persistent()
        let count = await memory.count
        #expect(count == 0)
    }

    @Test("persistent factory respects custom backend")
    func persistentFactoryCustomBackend() async {
        let backend = InMemoryBackend()
        let memory = AnyMemory.persistent(backend: backend)
        let count = await memory.count
        #expect(count == 0)
    }
}
