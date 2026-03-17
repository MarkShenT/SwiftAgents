// ToolBridgeHelper.swift
// Swarm Framework
//
// Existential opening helper for bridging Tool → AnyJSONTool.

import Foundation

// MARK: - Bridge Helper

/// Opens a `any Tool` existential and bridges the underlying concrete type to
/// the internal `AnyJSONTool` protocol.
///
/// Swift 5.7+ existential opening means the compiler infers the generic parameter
/// `T` as the concrete type stored inside an `any Tool` existential when the
/// existential is passed to a function whose parameter is typed `T: Tool`.
/// This lets call sites hold a heterogeneous `any Tool` and still arrive at a
/// properly typed `AnyJSONToolAdapter<T>` without a manual cast.
///
/// Usage inside `Sources/Swarm/` only — not part of the public V3 API surface.
///
/// ```swift
/// let tool: any Tool = MyTool()
/// let anyJSON: any AnyJSONTool = bridgeToolToAnyJSON(tool)
/// // Swift opens the existential → T inferred as MyTool
/// ```
///
/// - Parameter tool: A concrete `Tool` conformer. The generic parameter `T`
///   is inferred by the compiler — never pass it explicitly.
/// - Returns: An `AnyJSONToolAdapter<T>` that wraps `tool` and satisfies
///   the `AnyJSONTool` protocol.
@inlinable
internal func bridgeToolToAnyJSON<T: Tool>(_ tool: T) -> any AnyJSONTool {
    AnyJSONToolAdapter(tool)
}
