// AgentMemory.swift
// Swarm Framework
//
// Core protocol defining memory storage and retrieval for agents.

import Foundation

// MARK: - Memory

/// Protocol defining memory storage and retrieval for agents.
///
/// `Memory` provides the contract for storing conversation history
/// and retrieving relevant context for agent operations. All implementations
/// must be actors to ensure thread-safe access.
///
/// ## Conformance Requirements
///
/// - Must be an `actor` (inherited from protocol requirements)
/// - Must be `Sendable` for safe concurrent access
/// - All methods are implicitly `async` due to actor isolation
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
public protocol Memory: Actor, Sendable {
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

// MARK: - AnyMemory

/// Type-erased wrapper for any Memory implementation.
///
/// Useful when you need to store different memory types in collections
/// or pass them through APIs that don't support generics.
///
/// ## Usage
///
/// ```swift
/// let conversation = ConversationMemory(maxMessages: 50)
/// let erased = AnyMemory(conversation)
/// await erased.add(.user("Hello"))
/// ```
public actor AnyMemory: Memory {
    // MARK: Public

    public var count: Int {
        get async {
            await _count()
        }
    }

    public var isEmpty: Bool {
        get async {
            await _isEmpty()
        }
    }

    /// Creates a type-erased wrapper around any Memory.
    ///
    /// - Parameter memory: The memory implementation to wrap.
    public init(_ memory: some Memory) {
        _add = { message in await memory.add(message) }
        _context = { query, limit in await memory.context(for: query, tokenLimit: limit) }
        _allMessages = { await memory.allMessages() }
        _clear = { await memory.clear() }
        _count = { await memory.count }
        _isEmpty = { await memory.isEmpty }
    }

    public func add(_ message: MemoryMessage) async {
        await _add(message)
    }

    public func context(for query: String, tokenLimit: Int) async -> String {
        await _context(query, tokenLimit)
    }

    public func allMessages() async -> [MemoryMessage] {
        await _allMessages()
    }

    public func clear() async {
        await _clear()
    }

    // MARK: Private

    private let _add: @Sendable (MemoryMessage) async -> Void
    private let _context: @Sendable (String, Int) async -> String
    private let _allMessages: @Sendable () async -> [MemoryMessage]
    private let _clear: @Sendable () async -> Void
    private let _count: @Sendable () async -> Int
    private let _isEmpty: @Sendable () async -> Bool
}

// MARK: - AnyMemory Factory Methods

public extension AnyMemory {
    /// Creates an `AnyMemory` wrapping a `ConversationMemory`.
    ///
    /// - Parameter maxMessages: Maximum messages to retain (default: 100).
    /// - Returns: A type-erased memory backed by `ConversationMemory`.
    static func conversation(maxMessages: Int = 100) -> AnyMemory {
        AnyMemory(ConversationMemory(maxMessages: maxMessages))
    }

    /// Creates an `AnyMemory` wrapping a `SlidingWindowMemory`.
    ///
    /// - Parameter maxTokens: Maximum tokens to retain (default: 4000).
    /// - Returns: A type-erased memory backed by `SlidingWindowMemory`.
    static func slidingWindow(maxTokens: Int = 4000) -> AnyMemory {
        AnyMemory(SlidingWindowMemory(maxTokens: maxTokens))
    }

    /// Creates an `AnyMemory` wrapping a `VectorMemory`.
    ///
    /// - Parameters:
    ///   - embeddingProvider: Provider for generating text embeddings.
    ///   - similarityThreshold: Minimum similarity for results (0–1, default: 0.7).
    ///   - maxResults: Maximum results to return (default: 10).
    /// - Returns: A type-erased memory backed by `VectorMemory`.
    static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> AnyMemory {
        AnyMemory(VectorMemory(
            embeddingProvider: embeddingProvider,
            similarityThreshold: similarityThreshold,
            maxResults: maxResults
        ))
    }

    /// Creates an `AnyMemory` wrapping a `PersistentMemory`.
    ///
    /// Defaults to an `InMemoryBackend` when no backend is provided, making
    /// it suitable for testing and prototyping without database dependencies.
    ///
    /// - Parameters:
    ///   - backend: The storage backend (default: `InMemoryBackend()`).
    ///   - conversationId: Unique identifier for this conversation (default: random UUID).
    ///   - maxMessages: Maximum messages to retain; 0 means unlimited (default: 0).
    /// - Returns: A type-erased memory backed by `PersistentMemory`.
    static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> AnyMemory {
        AnyMemory(PersistentMemory(
            backend: backend,
            conversationId: conversationId,
            maxMessages: maxMessages
        ))
    }
}
