// AgentMemory.swift
// Swarm Framework
//
// Core protocol defining memory storage and retrieval for agents.

import Foundation

// MARK: - Memory

/// Protocol defining memory storage and retrieval for agents.
///
/// `Memory` provides the contract for storing conversation history
/// and retrieving relevant context for agent operations.
///
/// ## Conformance Requirements
///
/// - Must be `Sendable` for safe concurrent access
/// - All methods must be `async` to accommodate actor and non-actor implementations
///
/// Actor conformances (the recommended pattern) satisfy `Sendable` automatically.
/// Non-actor conformances are also valid when thread-safety is handled via other means.
///
/// ## Example Implementation
///
/// ```swift
/// public actor MyCustomMemory: Memory {
///     private var messages: [MemoryMessage] = []
///
///     public func add(_ message: MemoryMessage) async {
///         messages.append(message)
///     }
///
///     public func context(for query: String, tokenLimit: Int) async -> String {
///         MemoryMessage.formatContext(messages, tokenLimit: tokenLimit)
///     }
///
///     public func allMessages() async -> [MemoryMessage] {
///         messages
///     }
///
///     public func clear() async {
///         messages.removeAll()
///     }
///
///     public var count: Int { messages.count }
/// }
/// ```
public protocol Memory: Sendable {
    /// The number of messages currently stored.
    var count: Int { get async }

    /// Whether the memory contains no messages.
    ///
    /// Implementations should provide an efficient check that avoids
    /// fetching all messages when possible.
    var isEmpty: Bool { get async }

    /// Adds a message to memory.
    ///
    /// - Parameter message: The message to store.
    func add(_ message: MemoryMessage) async

    /// Retrieves context relevant to the query within token limits.
    ///
    /// The implementation determines how to select and format messages.
    /// Simple implementations may return recent messages; advanced ones
    /// may use semantic search or summarization.
    ///
    /// - Parameters:
    ///   - query: The query to find relevant context for.
    ///   - tokenLimit: Maximum tokens to include in the context.
    /// - Returns: A formatted string containing relevant context.
    func context(for query: String, tokenLimit: Int) async -> String

    /// Returns all messages currently in memory.
    ///
    /// - Returns: Array of all stored messages, typically in chronological order.
    func allMessages() async -> [MemoryMessage]

    /// Removes all messages from memory.
    func clear() async
}

// MARK: - MemoryMessage Context Formatting

public extension MemoryMessage {
    /// Formats messages into a context string within token limits.
    ///
    /// Processes messages from most recent to oldest, including as many
    /// as fit within the token budget. Messages are joined with double newlines.
    ///
    /// - Parameters:
    ///   - messages: Messages to format.
    ///   - tokenLimit: Maximum tokens allowed.
    ///   - tokenEstimator: Estimator for token counting.
    /// - Returns: Formatted context string with messages joined by double newlines.
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0

        // Process messages in reverse (most recent first) then reverse result
        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)

            if currentTokens + messageTokens <= tokenLimit {
                result.append(formatted)
                currentTokens += messageTokens
            } else {
                break
            }
        }

        return result.reversed().joined(separator: "\n\n")
    }

    /// Formats messages into a context string within token limits with a custom separator.
    ///
    /// - Parameters:
    ///   - messages: Messages to format.
    ///   - tokenLimit: Maximum tokens allowed.
    ///   - separator: String to join messages.
    ///   - tokenEstimator: Estimator for token counting.
    /// - Returns: Formatted context string.
    static func formatContext(
        _ messages: [MemoryMessage],
        tokenLimit: Int,
        separator: String,
        tokenEstimator: any TokenEstimator = CharacterBasedTokenEstimator.shared
    ) -> String {
        var result: [String] = []
        var currentTokens = 0
        let separatorTokens = tokenEstimator.estimateTokens(for: separator)

        for message in messages.reversed() {
            let formatted = message.formattedContent
            let messageTokens = tokenEstimator.estimateTokens(for: formatted)
            let totalNeeded = messageTokens + (result.isEmpty ? 0 : separatorTokens)

            if currentTokens + totalNeeded <= tokenLimit {
                result.append(formatted)
                currentTokens += totalNeeded
            } else {
                break
            }
        }

        return result.reversed().joined(separator: separator)
    }
}

// MARK: - Memory Factory Extensions (V3)

extension Memory where Self == ConversationMemory {
    /// Creates a `ConversationMemory` with a maximum message count.
    ///
    /// Enables dot-syntax at any `some Memory` call site:
    ///
    /// ```swift
    /// agent.withMemory(.conversation())
    /// agent.withMemory(.conversation(maxMessages: 50))
    /// ```
    ///
    /// - Parameter maxMessages: Maximum messages to retain (default: 100).
    /// - Returns: A `ConversationMemory` instance.
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory {
        ConversationMemory(maxMessages: maxMessages)
    }
}

extension Memory where Self == SlidingWindowMemory {
    /// Creates a `SlidingWindowMemory` with a maximum token count.
    ///
    /// Enables dot-syntax at any `some Memory` call site:
    ///
    /// ```swift
    /// agent.withMemory(.slidingWindow())
    /// agent.withMemory(.slidingWindow(maxTokens: 8000))
    /// ```
    ///
    /// - Parameter maxTokens: Maximum tokens to retain (default: 4000).
    /// - Returns: A `SlidingWindowMemory` instance.
    public static func slidingWindow(maxTokens: Int = 4000) -> SlidingWindowMemory {
        SlidingWindowMemory(maxTokens: maxTokens)
    }
}

extension Memory where Self == PersistentMemory {
    /// Creates a `PersistentMemory` with a pluggable storage backend.
    ///
    /// Defaults to an `InMemoryBackend`, which makes this suitable for
    /// testing and prototyping without any database dependencies.
    ///
    /// Enables dot-syntax at any `some Memory` call site:
    ///
    /// ```swift
    /// agent.withMemory(.persistent())
    /// agent.withMemory(.persistent(backend: myBackend, conversationId: "session-1"))
    /// ```
    ///
    /// - Parameters:
    ///   - backend: The storage backend (default: `InMemoryBackend()`).
    ///   - conversationId: Unique identifier for this conversation (default: random UUID).
    ///   - maxMessages: Maximum messages to retain; 0 means unlimited (default: 0).
    /// - Returns: A `PersistentMemory` instance.
    public static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> PersistentMemory {
        PersistentMemory(
            backend: backend,
            conversationId: conversationId,
            maxMessages: maxMessages
        )
    }
}

extension Memory where Self == HybridMemory {
    /// Creates a `HybridMemory` combining short-term and summarized long-term memory.
    ///
    /// Enables dot-syntax at any `some Memory` call site:
    ///
    /// ```swift
    /// agent.withMemory(.hybrid())
    /// agent.withMemory(.hybrid(configuration: .init(shortTermMaxMessages: 50)))
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Behavior configuration (default: `.default`).
    ///   - summarizer: Summarization service (default: `TruncatingSummarizer.shared`).
    /// - Returns: A `HybridMemory` instance.
    public static func hybrid(
        configuration: HybridMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> HybridMemory {
        HybridMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == SummaryMemory {
    /// Creates a `SummaryMemory` that automatically summarizes old messages.
    ///
    /// Enables dot-syntax at any `some Memory` call site:
    ///
    /// ```swift
    /// agent.withMemory(.summary())
    /// agent.withMemory(.summary(configuration: .init(recentMessageCount: 30)))
    /// ```
    ///
    /// - Parameters:
    ///   - configuration: Behavior configuration (default: `.default`).
    ///   - summarizer: Summarization service (default: `TruncatingSummarizer.shared`).
    /// - Returns: A `SummaryMemory` instance.
    public static func summary(
        configuration: SummaryMemory.Configuration = .default,
        summarizer: any Summarizer = TruncatingSummarizer.shared
    ) -> SummaryMemory {
        SummaryMemory(configuration: configuration, summarizer: summarizer)
    }
}

extension Memory where Self == VectorMemory {
    /// Creates a `VectorMemory` backed by semantic embeddings.
    ///
    /// Enables dot-syntax at any `some Memory` call site when an embedding
    /// provider is available:
    ///
    /// ```swift
    /// agent.withMemory(.vector(embeddingProvider: myProvider))
    /// agent.withMemory(.vector(embeddingProvider: myProvider, similarityThreshold: 0.8))
    /// ```
    ///
    /// - Parameters:
    ///   - embeddingProvider: Provider for generating text embeddings.
    ///   - similarityThreshold: Minimum similarity for results (0–1, default: 0.7).
    ///   - maxResults: Maximum results to return (default: 10).
    /// - Returns: A `VectorMemory` instance.
    public static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> VectorMemory {
        VectorMemory(
            embeddingProvider: embeddingProvider,
            similarityThreshold: similarityThreshold,
            maxResults: maxResults
        )
    }
}
