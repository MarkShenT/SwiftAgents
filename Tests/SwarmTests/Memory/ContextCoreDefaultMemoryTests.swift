import Foundation
import Testing
@testable import Swarm

@Suite("Default Composite Memory")
struct ContextCoreDefaultMemoryTests {
    @Test("Agent uses ContextCore + Wax memory by default on subsequent turns")
    func agentUsesContextCoreMemoryByDefault() async throws {
        let session = InMemorySession()
        let provider = MockInferenceProvider(responses: [
            "First reply",
            "Second reply"
        ])

        let agent = try Agent(
            tools: [],
            instructions: "You are a helpful assistant.",
            inferenceProvider: provider
        )

        _ = try await agent.run("Remember me", session: session)
        _ = try await agent.run("Do you remember what I said?", session: session)

        let messageCalls = await provider.generateMessageCalls
        #expect(messageCalls.count == 2)

        let secondMessages = messageCalls[1].messages
        let systemMessage = secondMessages.first(where: { $0.role == .system })

        #expect(systemMessage != nil)
        #expect(systemMessage?.content.contains("ContextCore Memory Context (primary)") == true)
        #expect(systemMessage?.content.contains("Wax Memory Context (secondary)") == true)
        #expect(systemMessage?.content.contains("Remember me") == true)
        #expect(systemMessage?.content.contains("First reply") == true)
    }

    @Test("DefaultAgentMemory seeds replayed history into both layers")
    func defaultCompositeMemorySeedsReplayIntoBothLayers() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        let replay = [
            MemoryMessage.user("alpha"),
            MemoryMessage.assistant("beta")
        ]

        await memory.importSessionHistory(replay)

        let workingMessages = await memory.workingMessages()
        let durableMessages = await memory.durableMessages()
        let allMessages = await memory.allMessages()

        #expect(await memory.count == 2)
        #expect(await memory.isEmpty == false)
        #expect(allMessages.map(\.content) == ["alpha", "beta"])
        #expect(workingMessages.map(\.content) == ["alpha", "beta"])
        #expect(durableMessages.map(\.content) == ["alpha", "beta"])
    }

    @Test("DefaultAgentMemory keeps layered context within the requested token budget")
    func defaultCompositeMemoryHonorsCompositeBudget() async throws {
        let url = try makeTemporaryWaxURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let counter = CountingPromptTokenCounter()
        let memory = try DefaultAgentMemory(
            configuration: .init(
                waxStoreURL: url
            )
        )

        let payload = String(repeating: "layered memory context ", count: 24)
        for index in 0 ..< 6 {
            await memory.add(.user("primary-\(index): \(payload)"))
            await memory.add(.assistant("secondary-\(index): \(payload)"))
        }

        let tokenLimit = 700
        let context = await AgentEnvironmentValues.$current.withValue(
            AgentEnvironment(promptTokenCounter: counter)
        ) {
            await memory.context(for: "layered memory context", tokenLimit: tokenLimit)
        }

        let workingMessages = await memory.workingMessages()
        let durableMessages = await memory.durableMessages()
        let exactCount = try await counter.countTokens(in: context)

        #expect(await counter.callCount > 0)
        #expect(exactCount <= tokenLimit)
        #expect(workingMessages.isEmpty == false)
        #expect(durableMessages.isEmpty == false)
        #expect(context.isEmpty == false)
    }
}

private actor CountingPromptTokenCounter: PromptTokenCounter {
    private var callCountStorage = 0

    var callCount: Int {
        callCountStorage
    }

    func countTokens(in text: String) async throws -> Int {
        callCountStorage += 1
        return max(1, text.count)
    }
}

private func makeTemporaryWaxURL() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swarm-default-memory-tests",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("wax-memory-\(UUID().uuidString).mv2s")
}
