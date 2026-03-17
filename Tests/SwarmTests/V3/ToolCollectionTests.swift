// ToolCollectionTests.swift
// SwarmTests
//
// TDD tests for ToolCollection and bridgeToolToAnyJSON (V3 API).

import Testing
@testable import Swarm

// MARK: - Mock Tool for Tests

/// A minimal concrete Tool implementation used exclusively in these tests.
private struct GreetingTool: Tool {
    struct Input: Codable, Sendable {
        let name: String
    }

    typealias Output = String

    let name = "greeting"
    let description = "Greets a person by name"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "name", description: "The person's name", type: .string)
    ]

    func execute(_ input: Input) async throws -> String {
        "Hello, \(input.name)!"
    }
}

/// A second distinct tool used for multi-tool storage tests.
private struct EchoBackTool: Tool {
    struct Input: Codable, Sendable {
        let message: String
    }

    typealias Output = String

    let name = "echo_back"
    let description = "Echoes back the given message"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "message", description: "Message to echo", type: .string)
    ]

    func execute(_ input: Input) async throws -> String {
        input.message
    }
}

// MARK: - ToolCollection Tests

@Suite("ToolCollection")
struct ToolCollectionTests {

    // MARK: - Empty Collection

    @Test("ToolCollection.empty has zero tools in storage")
    func emptyCollectionHasZeroStorage() {
        let collection = ToolCollection.empty
        #expect(collection.storage.isEmpty)
        #expect(collection.storage.count == 0)
    }

    // MARK: - Sendable Conformance

    @Test("ToolCollection is Sendable — can be captured across concurrency boundaries")
    func toolCollectionIsSendable() async {
        let collection = ToolCollection.empty
        // The mere fact this compiles without a warning under strict concurrency
        // validates Sendable conformance. We verify it at runtime by crossing
        // an async boundary.
        let count = await Task.detached {
            collection.storage.count
        }.value
        #expect(count == 0)
    }

    // MARK: - Internal Storage

    @Test("ToolCollection can be initialised with tools in storage")
    func collectionWithToolsInStorage() {
        let tool = GreetingTool()
        let adapter = AnyJSONToolAdapter(tool)
        let collection = ToolCollection(storage: [adapter])

        #expect(collection.storage.count == 1)
        #expect(collection.storage.first?.name == "greeting")
    }

    @Test("ToolCollection stores multiple tools preserving order")
    func collectionPreservesInsertionOrder() {
        let greeting = AnyJSONToolAdapter(GreetingTool())
        let echo = AnyJSONToolAdapter(EchoBackTool())
        let collection = ToolCollection(storage: [greeting, echo])

        #expect(collection.storage.count == 2)
        #expect(collection.storage[0].name == "greeting")
        #expect(collection.storage[1].name == "echo_back")
    }

    // MARK: - Bridge Helper: Concrete Generic Path

    @Test("bridgeToolToAnyJSON works with a concrete Tool type")
    func bridgeConcreteToolToAnyJSON() {
        let tool = GreetingTool()
        let bridged: any AnyJSONTool = bridgeToolToAnyJSON(tool)

        #expect(bridged.name == "greeting")
        #expect(bridged.description == "Greets a person by name")
        #expect(bridged.parameters.count == 1)
        #expect(bridged.parameters.first?.name == "name")
    }

    // MARK: - Bridge Helper: Existential Opening Path

    @Test("bridgeToolToAnyJSON works with an `any Tool` existential via existential opening")
    func bridgeExistentialToolToAnyJSON() {
        // `any Tool` existential — the compiler opens it to infer the concrete T.
        let tool: any Tool = GreetingTool()
        // Swift 5.7+ existential opening: passing `any Tool` to a generic <T: Tool>
        // opens the existential and infers T as the underlying GreetingTool.
        let bridged = openAndBridge(tool)

        #expect(bridged.name == "greeting")
    }

    // MARK: - Bridge Helper: Execution Correctness

    @Test("A bridged tool executes correctly and returns the expected result")
    func bridgedToolExecutesCorrectly() async throws {
        let tool = GreetingTool()
        let bridged: any AnyJSONTool = bridgeToolToAnyJSON(tool)

        let arguments: [String: SendableValue] = ["name": .string("World")]
        let result = try await bridged.execute(arguments: arguments)

        #expect(result == .string("Hello, World!"))
    }

    @Test("A bridged EchoBackTool executes correctly")
    func bridgedEchoToolExecutesCorrectly() async throws {
        let tool = EchoBackTool()
        let bridged: any AnyJSONTool = bridgeToolToAnyJSON(tool)

        let arguments: [String: SendableValue] = ["message": .string("ping")]
        let result = try await bridged.execute(arguments: arguments)

        #expect(result == .string("ping"))
    }
}

// MARK: - Existential Opening Helper (test-local)

/// Opens a `any Tool` existential using Swift 5.7+ generic inference and bridges
/// the concrete underlying type to `AnyJSONTool`.
///
/// This helper exists so the test can exercise the `any Tool` → existential opening
/// → `bridgeToolToAnyJSON<T: Tool>` code path.
private func openAndBridge(_ tool: any Tool) -> any AnyJSONTool {
    bridgeToolToAnyJSON(tool)
}
