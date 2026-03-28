// ProviderFactoryTests.swift
// SwarmTests
//
// TDD tests for InferenceProvider static factory methods (V3 API).

import Testing
@testable import Swarm

@Suite("InferenceProvider Factory Methods")
struct ProviderFactoryTests {

    @Test("anthropic factory creates ConduitProviderSelection")
    func anthropicFactory() {
        let provider = ConduitProviderSelection.anthropic(apiKey: "test-key", model: "claude-opus-4-6")
        let _: any InferenceProvider = provider
    }

    @Test("openAI factory creates provider")
    func openAIFactory() {
        let provider = ConduitProviderSelection.openAI(apiKey: "test-key", model: "gpt-4o")
        let _: any InferenceProvider = provider
    }

    @Test("ollama factory creates provider")
    func ollamaFactory() {
        let provider = ConduitProviderSelection.ollama(model: "llama3.2", baseURL: "http://localhost:11434")
        let _: any InferenceProvider = provider
    }

    @Test("gemini factory creates provider")
    func geminiFactory() {
        let provider = ConduitProviderSelection.gemini(apiKey: "test-key", model: "gemini-2.0-flash")
        let _: any InferenceProvider = provider
    }

#if CONDUIT_TRAIT_MLX && canImport(MLX)
    @Test("mlx factory creates provider")
    func mlxFactory() {
        let provider = ConduitProviderSelection.mlx(model: "mlx-community/Llama-3.2-1B-Instruct-4bit")
        let _: any InferenceProvider = provider
    }
#endif

    @Test("dot-syntax works in function parameter context")
    func dotSyntaxInFunctionContext() {
        func takesProvider(_ p: some InferenceProvider) {}
        takesProvider(ConduitProviderSelection.anthropic(apiKey: "key", model: "claude-opus-4-6"))
    }
}
