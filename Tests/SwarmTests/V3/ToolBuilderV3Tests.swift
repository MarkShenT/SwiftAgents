// ToolBuilderV3Tests.swift
// SwarmTests
//
// TDD tests for ToolBuilder producing ToolCollection (V3 API).

import Testing
@testable import Swarm

// MARK: - Minimal Tool Conformers

/// Minimal Tool conformer used in these tests.
private struct AlphaTool: Tool {
    struct Input: Codable, Sendable { let query: String }
    typealias Output = String

    let name = "alpha"
    let description = "Alpha tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "query", description: "Query string", type: .string)
    ]

    func execute(_ input: Input) async throws -> String { input.query }
}

/// A second distinct Tool conformer.
private struct BetaTool: Tool {
    struct Input: Codable, Sendable { let value: Int }
    typealias Output = String

    let name = "beta"
    let description = "Beta tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "value", description: "Integer value", type: .int)
    ]

    func execute(_ input: Input) async throws -> String { "\(input.value)" }
}

/// A third Tool conformer used for conditional/array tests.
private struct GammaTool: Tool {
    struct Input: Codable, Sendable { let flag: Bool }
    typealias Output = String

    let name = "gamma"
    let description = "Gamma tool"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "flag", description: "Boolean flag", type: .bool)
    ]

    func execute(_ input: Input) async throws -> String { "\(input.flag)" }
}

// MARK: - ToolBuilder V3 Tests

@Suite("ToolBuilder V3 — produces ToolCollection")
struct ToolBuilderV3Tests {

    // MARK: 1. Empty builder

    @Test("Empty builder body produces empty ToolCollection")
    func emptyBuilderProducesEmptyCollection() {
        @ToolBuilder
        func noTools() -> ToolCollection {}

        let collection = noTools()
        #expect(collection.storage.isEmpty)
    }

    // MARK: 2. Single typed Tool

    @Test("Single concrete Tool in builder produces one-element ToolCollection")
    func singleTypedToolProducesSingleElementCollection() {
        @ToolBuilder
        func oneTyped() -> ToolCollection {
            AlphaTool()
        }

        let collection = oneTyped()
        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "alpha")
    }

    // MARK: 3. Multiple Tools

    @Test("Multiple concrete Tools in builder preserve insertion order")
    func multipleToolsPreserveOrder() {
        @ToolBuilder
        func twoTyped() -> ToolCollection {
            AlphaTool()
            BetaTool()
        }

        let collection = twoTyped()
        #expect(collection.storage.count == 2)
        #expect(collection.storage[0].name == "alpha")
        #expect(collection.storage[1].name == "beta")
    }

    @Test("Three tools in builder all appear in storage")
    func threeToolsAllPresent() {
        @ToolBuilder
        func threeTyped() -> ToolCollection {
            AlphaTool()
            BetaTool()
            GammaTool()
        }

        let collection = threeTyped()
        #expect(collection.storage.count == 3)
        let names = collection.storage.map(\.name)
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
        #expect(names.contains("gamma"))
    }

    // MARK: 4. Conditional tools (if / else)

    @Test("Conditional 'if true' branch includes the tool")
    func conditionalIfTrueIncludesTool() {
        let include = true

        @ToolBuilder
        func conditional() -> ToolCollection {
            if include {
                GammaTool()
            }
        }

        let collection = conditional()
        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "gamma")
    }

    @Test("Conditional 'if false' branch produces empty collection")
    func conditionalIfFalseProducesEmpty() {
        let include = false

        @ToolBuilder
        func conditional() -> ToolCollection {
            if include {
                GammaTool()
            }
        }

        let collection = conditional()
        #expect(collection.storage.isEmpty)
    }

    @Test("if/else selects the correct branch")
    func conditionalIfElseSelectsCorrectBranch() {
        let useAlpha = true

        @ToolBuilder
        func branch() -> ToolCollection {
            if useAlpha {
                AlphaTool()
            } else {
                BetaTool()
            }
        }

        let collection = branch()
        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "alpha")
    }

    @Test("if/else selects second branch when condition is false")
    func conditionalIfElseSelectsSecondBranch() {
        let useAlpha = false

        @ToolBuilder
        func branch() -> ToolCollection {
            if useAlpha {
                AlphaTool()
            } else {
                BetaTool()
            }
        }

        let collection = branch()
        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "beta")
    }

    // MARK: 5. any Tool existential

    @Test("any Tool existential in builder is bridged correctly")
    func anyToolExistentialIsBridged() {
        let tool: any Tool = AlphaTool()

        @ToolBuilder
        func existential() -> ToolCollection {
            tool
        }

        let collection = existential()
        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "alpha")
    }

    @Test("Mixed concrete and existential tools both appear in collection")
    func mixedConcreteAndExistential() {
        let anyTool: any Tool = BetaTool()

        @ToolBuilder
        func mixed() -> ToolCollection {
            AlphaTool()
            anyTool
        }

        let collection = mixed()
        #expect(collection.storage.count == 2)
        #expect(collection.storage[0].name == "alpha")
        #expect(collection.storage[1].name == "beta")
    }

    // MARK: 6. Array of tools

    @Test("[any Tool] array in builder produces all tools in collection")
    func arrayOfToolsProducesAllTools() {
        let tools: [any Tool] = [AlphaTool(), BetaTool(), GammaTool()]

        @ToolBuilder
        func fromArray() -> ToolCollection {
            tools
        }

        let collection = fromArray()
        #expect(collection.storage.count == 3)
        let names = collection.storage.map(\.name)
        #expect(names == ["alpha", "beta", "gamma"])
    }

    @Test("Empty [any Tool] array produces empty collection")
    func emptyArrayProducesEmptyCollection() {
        let tools: [any Tool] = []

        @ToolBuilder
        func fromEmpty() -> ToolCollection {
            tools
        }

        let collection = fromEmpty()
        #expect(collection.storage.isEmpty)
    }

    // MARK: 7. Agent init integration

    @Test("Agent V3 init with @ToolBuilder produces correct tool count")
    func agentV3InitIntegration() throws {
        let agent = try Agent("Be helpful.") {
            AlphaTool()
            BetaTool()
        }
        #expect(agent.tools.count == 2)
        let names = agent.tools.map(\.name)
        #expect(names.contains("alpha"))
        #expect(names.contains("beta"))
    }

    @Test("Agent V3 init with empty @ToolBuilder closure produces zero tools")
    func agentV3InitEmptyBuilder() throws {
        let agent = try Agent("Be helpful.") {
            // intentionally empty
        }
        #expect(agent.tools.isEmpty)
    }

    @Test("Agent V3 init default (no trailing closure) produces zero tools")
    func agentV3InitNoTrailingClosure() throws {
        let agent = try Agent("Be helpful.")
        #expect(agent.tools.isEmpty)
    }
}
