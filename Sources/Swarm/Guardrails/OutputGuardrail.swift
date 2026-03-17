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
/// let guardrail = OutputGuard("content_filter") { output in
///     if output.contains("badword") {
///         return .tripwire(
///             message: "Profanity detected"
///         )
///     }
///     return .passed()
/// }
///
/// let result = try await guardrail.validate(
///     "Agent response text",
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

// MARK: - OutputGuard

/// A lightweight, closure-based `OutputGuardrail` with a concise API.
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

// MARK: - V3 Protocol Factory Extensions

extension OutputGuardrail where Self == OutputGuard {
    /// Creates a max-length output guardrail.
    public static func maxLength(_ maxLength: Int, name: String = "MaxOutputLengthGuardrail") -> OutputGuard {
        OutputGuard.maxLength(maxLength, name: name)
    }

    /// Creates a custom output guardrail.
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> OutputGuard {
        OutputGuard.custom(name, validate)
    }
}
