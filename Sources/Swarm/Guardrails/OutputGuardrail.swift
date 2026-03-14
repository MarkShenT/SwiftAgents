// OutputGuardrail.swift
// Swarm Framework
//
// Protocol and implementations for validating agent output before returning to users.

import Foundation

/// Type alias for output validation handler closures.
public typealias OutputValidationHandler = @Sendable (String, any AgentRuntime, AgentContext?) async throws -> GuardrailResult

// MARK: - OutputGuardrail

/// Protocol for validating agent output before returning to users.
///
/// `OutputGuardrail` enables validation and filtering of agent outputs to ensure they meet
/// safety, quality, or policy requirements. Output guardrails receive the agent's output text,
/// the agent instance, and optional context for making validation decisions.
///
/// Common use cases:
/// - Content filtering (profanity, sensitive data)
/// - Quality checks (minimum length, coherence)
/// - Policy compliance (tone, formatting)
/// - PII detection and redaction
///
/// Example:
/// ```swift
/// let guardrail = ClosureOutputGuardrail(name: "content_filter") { output, agent, context in
///     if output.contains("badword") {
///         return .tripwire(
///             message: "Profanity detected",
///             outputInfo: .dictionary(["word": .string("badword")])
///         )
///     }
///     return .passed()
/// }
///
/// let result = try await guardrail.validate(
///     "LegacyAgent response text",
///     agent: myAgent,
///     context: context
/// )
///
/// if result.tripwireTriggered {
///     print("Output blocked: \(result.message ?? "")")
/// }
/// ```
public protocol OutputGuardrail: Guardrail {
    /// The name of this guardrail for identification and logging.
    var name: String { get }

    /// Validates an agent's output.
    ///
    /// - Parameters:
    ///   - output: The output text from the agent to validate.
    ///   - agent: The agent that produced this output.
    ///   - context: Optional orchestration context with shared state.
    /// - Returns: A result indicating whether the output passed validation.
    /// - Throws: An error if validation fails unexpectedly.
    func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - ClosureOutputGuardrail

/// A closure-based implementation of `OutputGuardrail`.
///
/// `ClosureOutputGuardrail` wraps a validation closure, making it easy to create
/// custom output guardrails without defining new types.
///
/// The closure receives:
/// - `output`: The agent's output text
/// - `agent`: The agent instance that produced the output
/// - `context`: Optional shared orchestration context
///
/// The closure is marked `@Sendable` to ensure thread-safety across async boundaries.
///
/// Example:
/// ```swift
/// // PII detection guardrail
/// let piiGuardrail = ClosureOutputGuardrail(name: "pii_detector") { output, agent, context in
///     let patterns = ["\\d{3}-\\d{2}-\\d{4}", "\\d{16}"] // SSN, credit card
///     for pattern in patterns {
///         if let _ = output.range(of: pattern, options: .regularExpression) {
///             return .tripwire(
///                 message: "PII detected in output",
///                 outputInfo: .dictionary(["pattern": .string(pattern)])
///             )
///         }
///     }
///     return .passed(message: "No PII detected")
/// }
///
/// // Length validation
/// let lengthGuardrail = ClosureOutputGuardrail(name: "min_length") { output, _, _ in
///     if output.count < 10 {
///         return .tripwire(message: "Output too short")
///     }
///     return .passed()
/// }
///
/// // Context-aware validation
/// let contextGuardrail = ClosureOutputGuardrail(name: "strict_mode") { output, _, context in
///     if let mode = await context?.get("validation_mode")?.stringValue, mode == "strict" {
///         // Apply stricter validation
///         if output.contains("forbidden") {
///             return .tripwire(message: "Forbidden content in strict mode")
///         }
///     }
///     return .passed()
/// }
/// ```
// MARK: - OutputGuard

/// A lightweight, closure-based `OutputGuardrail` with a concise API.
///
/// Prefer `OutputGuard` over `ClosureOutputGuardrail` for new code.
///
/// Examples:
/// ```swift
/// // Minimal signature
/// let guardrail = OutputGuard("block_bad_words") { output in
///     output.contains("BAD") ? .tripwire(message: "blocked") : .passed()
/// }
///
/// // Context-aware
/// let strict = OutputGuard("strict_mode") { output, context in
///     let enabled = await context?.get("strict")?.boolValue ?? false
///     return enabled && output.contains("forbidden") ? .tripwire(message: "blocked") : .passed()
/// }
/// ```
public struct OutputGuard: OutputGuardrail, Sendable {
    public let name: String

    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, _ in
            try await validate(output)
        }
    }

    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { output, _, context in
            try await validate(output, context)
        }
    }

    public init(
        _ name: String,
        _ validate: @escaping OutputValidationHandler
    ) {
        self.name = name
        handler = validate
    }

    public func validate(_ output: String, agent: any AgentRuntime, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(output, agent, context)
    }

    private let handler: OutputValidationHandler
}

// MARK: - OutputGuard Static Factories

public extension OutputGuard {
    /// Creates a guardrail that checks output length.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inferenceProvider: provider,
    ///     outputGuardrails: [OutputGuard.maxLength(2000)]
    /// )
    /// ```
    static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard(name) { output in
            if output.count > maxLength {
                return .tripwire(
                    message: "Output exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(output.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Creates a custom output guardrail from a closure.
    ///
    /// Example:
    /// ```swift
    /// let noPII = OutputGuard.custom("no_pii") { output in
    ///     output.contains("SSN") ? .tripwire(message: "PII detected") : .passed()
    /// }
    /// ```
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard(name, validate)
    }
}
