import Foundation

/// Retrieval contract for memory implementations that support item-aware budgeting.
public struct MemoryQuery: Sendable, Equatable {
    /// User input or search text used to retrieve relevant memory.
    public let text: String

    /// Total token budget available to the memory implementation.
    public let tokenLimit: Int

    /// Maximum number of retrieved items to include.
    public let maxItems: Int

    /// Maximum token budget for any single retrieved item.
    public let maxItemTokens: Int

    public init(
        text: String,
        tokenLimit: Int,
        maxItems: Int,
        maxItemTokens: Int
    ) {
        self.text = text
        self.tokenLimit = max(0, tokenLimit)
        self.maxItems = max(1, maxItems)
        self.maxItemTokens = max(1, maxItemTokens)
    }
}

/// Optional memory extension for retrieval implementations that need more than a token limit.
public protocol MemoryRetrievalPolicyAware: Memory {
    /// Retrieves context relevant to the query while respecting item-level budgets.
    func context(for query: MemoryQuery) async -> String
}

/// Optional policy hook for memories that should not ingest session history automatically.
public protocol MemorySessionImportPolicy: Sendable {
    /// Whether the agent runtime may seed session history into this memory store.
    var allowsAutomaticSessionSeeding: Bool { get }
}
