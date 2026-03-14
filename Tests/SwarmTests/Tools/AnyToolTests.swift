// AnyToolTests.swift
// SwarmTests
//
// Verifies AnyJSONTool guardrail forwarding still works after AnyTool removal.

@testable import Swarm
import Testing

@Suite("AnyJSONTool Guardrail Tests")
struct AnyToolTests {
    private struct GuardrailedTool: AnyJSONTool {
        let name: String = "guarded"
        let description: String = "A tool with guardrails"
        let parameters: [ToolParameter] = []
        let inputGuardrails: [any ToolInputGuardrail]
        let outputGuardrails: [any ToolOutputGuardrail]

        init(
            inputGuardrails: [any ToolInputGuardrail] = [],
            outputGuardrails: [any ToolOutputGuardrail] = []
        ) {
            self.inputGuardrails = inputGuardrails
            self.outputGuardrails = outputGuardrails
        }

        func execute(arguments _: [String: SendableValue]) async throws -> SendableValue {
            .string("ok")
        }
    }

    @Test("AnyJSONTool forwards input/output guardrails")
    func forwardsGuardrails() {
        let input = ClosureToolInputGuardrail(name: "tripwire") { _ in
            .tripwire(message: "blocked")
        }
        let output = ClosureToolOutputGuardrail(name: "output_check") { _, _ in
            .passed()
        }

        let tool = GuardrailedTool(inputGuardrails: [input], outputGuardrails: [output])

        #expect(tool.inputGuardrails.count == 1)
        #expect(tool.outputGuardrails.count == 1)
    }

    @Test("ToolRegistry executes guardrails for AnyJSONTool tools")
    func registryRunsGuardrailsForWrappedTool() async throws {
        let input = ClosureToolInputGuardrail(name: "tripwire") { _ in
            .tripwire(message: "blocked")
        }

        let tool = GuardrailedTool(inputGuardrails: [input])
        let registry = try ToolRegistry(tools: [tool])

        do {
            _ = try await registry.execute(toolNamed: tool.name, arguments: [:])
            Issue.record("Expected tool guardrail tripwire to throw")
        } catch let error as GuardrailError {
            #expect({
                if case .toolInputTripwireTriggered = error { return true }
                return false
            }(), "Expected GuardrailError.toolInputTripwireTriggered, got: \(error)")
        }
    }
}
