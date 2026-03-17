// InputGuardrail.swift
// Swarm Framework
//
// Input validation guardrails for agent systems.
// Provides validation and safety checks for agent inputs before processing.

import Foundation

/// Type alias for input validation handler closures.
public typealias InputValidationHandler = @Sendable (String, AgentContext?) async throws -> GuardrailResult

// MARK: - InputGuardrail

/// Protocol for input validation guardrails.
///
/// `InputGuardrail` defines the contract for validating agent inputs before they are processed.
/// Guardrails can check for sensitive data, malicious content, policy violations, or any
/// custom validation logic.
///
/// Guardrails are composable and can be chained together to create complex validation pipelines.
/// They return a `GuardrailResult` indicating whether the input passed validation or triggered
/// a tripwire.
///
/// Example:
/// ```swift
/// struct SensitiveDataGuardrail: InputGuardrail {
///     let name = "SensitiveDataGuardrail"
///
///     func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
///         if input.contains("SSN:") || input.contains("password:") {
///             return .tripwire(message: "Sensitive data detected")
///         }
///         return .passed()
///     }
/// }
/// ```
public protocol InputGuardrail: Guardrail {
    /// The name of this guardrail for identification and logging.
    var name: String { get }

    /// Validates the input and returns a result.
    ///
    /// - Parameters:
    ///   - input: The input string to validate.
    ///   - context: Optional agent context for validation decisions.
    /// - Returns: A result indicating whether validation passed or triggered a tripwire.
    /// - Throws: Validation errors if the check cannot be completed.
    func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult
}

// MARK: - InputGuard

/// A lightweight, closure-based `InputGuardrail` with a concise API.
public struct InputGuard: InputGuardrail, Sendable {
    public let name: String

    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = { input, _ in
            try await validate(input)
        }
    }

    public init(
        _ name: String,
        _ validate: @escaping @Sendable (String, AgentContext?) async throws -> GuardrailResult
    ) {
        self.name = name
        handler = validate
    }

    public func validate(_ input: String, context: AgentContext?) async throws -> GuardrailResult {
        try await handler(input, context)
    }

    private let handler: InputValidationHandler
}

// MARK: - InputGuard Static Factories

public extension InputGuard {
    /// Creates a guardrail that checks input length.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inferenceProvider: provider,
    ///     inputGuardrails: [InputGuard.maxLength(500)]
    /// )
    /// ```
    static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.count > maxLength {
                return .tripwire(
                    message: "Input exceeds maximum length of \(maxLength)",
                    metadata: ["length": .int(input.count), "limit": .int(maxLength)]
                )
            }
            return .passed()
        }
    }

    /// Creates a guardrail that rejects empty inputs.
    ///
    /// Example:
    /// ```swift
    /// let agent = Agent(
    ///     instructions: "Assistant",
    ///     inferenceProvider: provider,
    ///     inputGuardrails: [InputGuard.notEmpty()]
    /// )
    /// ```
    static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard(name) { input in
            if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .tripwire(message: "Input cannot be empty")
            }
            return .passed()
        }
    }

    /// Creates a custom input guardrail from a closure.
    ///
    /// Example:
    /// ```swift
    /// let noNumbers = InputGuard.custom("no_numbers") { input in
    ///     input.rangeOfCharacter(from: .decimalDigits) == nil
    ///         ? .passed()
    ///         : .tripwire(message: "Numbers not allowed")
    /// }
    /// ```
    static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard(name, validate)
    }
}

// MARK: - V3 Protocol Factory Extensions

extension InputGuardrail where Self == InputGuard {
    /// Creates a max-length input guardrail.
    public static func maxLength(_ maxLength: Int, name: String = "MaxLengthGuardrail") -> InputGuard {
        InputGuard.maxLength(maxLength, name: name)
    }

    /// Creates a not-empty input guardrail.
    public static func notEmpty(name: String = "NotEmptyGuardrail") -> InputGuard {
        InputGuard.notEmpty(name: name)
    }

    /// Creates a custom input guardrail.
    public static func custom(
        _ name: String,
        _ validate: @escaping @Sendable (String) async throws -> GuardrailResult
    ) -> InputGuard {
        InputGuard.custom(name, validate)
    }
}
