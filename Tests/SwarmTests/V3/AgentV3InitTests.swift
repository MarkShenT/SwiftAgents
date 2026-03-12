// AgentV3InitTests.swift
// SwarmTests
//
// TDD tests for V3 canonical Agent init with @ToolBuilder trailing closure.

import Testing
@testable import Swarm

@Suite("Agent V3 Canonical Init")
struct AgentV3InitTests {
    @Test("minimal init - instructions only")
    func minimalInit() throws {
        let agent = try Agent("Be helpful.")
        #expect(agent.instructions == "Be helpful.")
        #expect(agent.name == "Agent")
    }

    @Test("init with custom name via configuration")
    func initWithName() throws {
        let agent = try Agent("Be helpful.", configuration: .default.name("Helper"))
        #expect(agent.instructions == "Be helpful.")
        #expect(agent.name == "Helper")
    }

    @Test("init with empty tool builder closure")
    func initWithEmptyToolBuilder() throws {
        let agent = try Agent("Be helpful.") {
            // empty builder
        }
        #expect(agent.instructions == "Be helpful.")
        #expect(agent.tools.isEmpty)
    }

    @Test("init with tool builder containing tools")
    func initWithToolBuilderTools() throws {
        let agent = try Agent("Be helpful.") {
            MockTool(name: "tool_a")
            MockTool(name: "tool_b")
        }
        #expect(agent.instructions == "Be helpful.")
        #expect(agent.tools.count == 2)
    }

    @Test("existing labeled init still works")
    func existingInitStillWorks() throws {
        let agent = try Agent(tools: [], instructions: "Old style.")
        #expect(agent.instructions == "Old style.")
    }

    @Test("V3 init with all parameters")
    func initWithAllParameters() throws {
        let agent = try Agent(
            "Full config.",
            configuration: .default.name("Full").maxIterations(5),
            inputGuardrails: [],
            outputGuardrails: [],
            handoffs: []
        ) {
            MockTool(name: "tool_c")
        }
        #expect(agent.instructions == "Full config.")
        #expect(agent.name == "Full")
        #expect(agent.tools.count == 1)
    }
}
