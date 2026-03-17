// ToolCollection.swift
// Swarm Framework
//
// Opaque tool collection produced by @ToolBuilder.

import Foundation

// MARK: - ToolCollection

/// An opaque collection of tools built by `@ToolBuilder`.
///
/// You never create `ToolCollection` directly — it is produced by the `@ToolBuilder`
/// result builder and consumed by `Agent` initializers and modifiers. Keeping the
/// internal storage type-erased behind `any AnyJSONTool` lets the V3 API hide
/// `AnyJSONTool` from the public surface while still forwarding tools to the
/// inference runtime.
///
/// ```swift
/// let tools = ToolCollection.empty          // zero tools
/// let agent = Agent("Be helpful.") {
///     WeatherTool()
///     SearchTool()
/// }
/// // The trailing closure produces a ToolCollection automatically.
/// ```
public struct ToolCollection: Sendable {

    // MARK: Internal

    /// The type-erased tools held in this collection.
    ///
    /// Access is intentionally `internal` — callers inside `Sources/Swarm/` can
    /// read the storage to build tool registries or pass schemas to inference
    /// providers, but the concrete `AnyJSONTool` protocol is not part of the
    /// public V3 API surface.
    internal let storage: [any AnyJSONTool]

    // MARK: Public

    /// An empty tool collection with no registered tools.
    public static let empty = ToolCollection(storage: [])

    // MARK: Internal Init

    /// Creates a `ToolCollection` backed by the given type-erased tools.
    ///
    /// - Parameter storage: The tools to store. Typically produced by
    ///   `bridgeToolToAnyJSON` or by wrapping `AnyJSONTool` values directly.
    internal init(storage: [any AnyJSONTool]) {
        self.storage = storage
    }
}
