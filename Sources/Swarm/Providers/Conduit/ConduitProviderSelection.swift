// ConduitProviderSelection.swift
// Swarm Framework
//
// Minimal Conduit-backed provider selection for Swarm.

import Conduit
import Foundation

/// Convenience selection for Conduit-backed inference providers.
///
/// This hides Conduit types while keeping a lightweight call-site API.
public enum ConduitProviderSelection: Sendable, InferenceProvider {
    case provider(any InferenceProvider)

    /// Creates a Conduit-backed Anthropic provider.
    public static func anthropic(apiKey: String, model: String) -> ConduitProviderSelection {
        let provider = AnthropicProvider(apiKey: apiKey)
        let modelID = AnthropicModelID(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    /// Creates a Conduit-backed OpenAI provider.
    public static func openAI(apiKey: String, model: String) -> ConduitProviderSelection {
        let configuration = OpenAIConfiguration.openAI(apiKey: apiKey)
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    /// Creates a Conduit-backed OpenRouter provider.
    public static func openRouter(
        apiKey: String,
        model: String
    ) -> ConduitProviderSelection {
        openRouter(apiKey: apiKey, model: model, routing: nil)
    }

    /// Creates a Conduit-backed OpenRouter provider with routing configuration.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The model identifier (e.g. `"anthropic/claude-3.5-sonnet"`).
    ///   - configure: Closure to customize OpenRouter routing preferences.
    ///
    /// ```swift
    /// let provider: some InferenceProvider = .openRouter(apiKey: key, model: "...") { routing in
    ///     routing.providers = [.anthropic]
    /// }
    /// ```
    public static func openRouter(
        apiKey: String,
        model: String,
        configure: (inout OpenRouterRouting) -> Void
    ) -> ConduitProviderSelection {
        var routing = OpenRouterRouting()
        configure(&routing)
        return openRouter(apiKey: apiKey, model: model, routing: routing)
    }

    /// Creates a Conduit-backed Ollama provider.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`).
    public static func ollama(model: String) -> ConduitProviderSelection {
        ollama(model: model, settings: .default)
    }

    /// Creates a Conduit-backed Ollama provider with closure-based configuration.
    ///
    /// - Parameters:
    ///   - model: The Ollama model name (e.g. `"llama3.2"`, `"mistral"`).
    ///   - configure: Closure to customize Ollama connection settings.
    ///
    /// ```swift
    /// let provider: some InferenceProvider = .ollama(model: "mistral") { settings in
    ///     settings.host = "127.0.0.1"
    ///     settings.port = 11435
    /// }
    /// ```
    public static func ollama(
        model: String,
        configure: (inout OllamaSettings) -> Void
    ) -> ConduitProviderSelection {
        var settings = OllamaSettings.default
        configure(&settings)
        return ollama(model: model, settings: settings)
    }

    /// Creates a Conduit-backed Ollama provider using a base URL string.
    ///
    /// - Parameters:
    ///   - model: The model name to use (e.g. `"llama3.2"`).
    ///   - baseURL: The full base URL of the Ollama server (e.g. `"http://localhost:11434"`).
    ///     Host and port are parsed from this URL; path components are ignored.
    public static func ollama(
        model: String,
        baseURL: String
    ) -> ConduitProviderSelection {
        var settings = OllamaSettings.default
        if let url = URL(string: baseURL), let host = url.host {
            settings.host = host
            if let port = url.port {
                settings.port = port
            }
        }
        return ollama(model: model, settings: settings)
    }

    /// Creates a Conduit-backed Gemini provider via OpenRouter.
    ///
    /// Gemini models are accessed through OpenRouter using the `google/<model>` namespace.
    /// The `apiKey` should be your OpenRouter API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your OpenRouter API key.
    ///   - model: The Gemini model identifier, e.g. `"gemini-2.0-flash"`.
    ///     This is automatically prefixed with `"google/"` when routing through OpenRouter.
    public static func gemini(
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) -> ConduitProviderSelection {
        let routedModel = model.hasPrefix("google/") ? model : "google/\(model)"
        return openRouter(apiKey: apiKey, model: routedModel)
    }

    /// Exposes the underlying inference provider.
    public func makeProvider() -> any InferenceProvider {
        switch self {
        case let .provider(provider):
            return provider
        }
    }

    public func generate(prompt: String, options: InferenceOptions) async throws -> String {
        try await makeProvider().generate(prompt: prompt, options: options)
    }

    public func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        makeProvider().stream(prompt: prompt, options: options)
    }

    public func generateWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse {
        try await makeProvider().generateWithToolCalls(prompt: prompt, tools: tools, options: options)
    }

    // MARK: - Internal Helpers

    static func openRouter(
        apiKey: String,
        model: String,
        routing: OpenRouterRouting?
    ) -> ConduitProviderSelection {
        var configuration = OpenAIConfiguration.openRouter(apiKey: apiKey)
        if let routing {
            configuration = configuration.routing(routing.toConduit())
        }
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID.openRouter(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }

    static func ollama(
        model: String,
        settings: OllamaSettings
    ) -> ConduitProviderSelection {
        let configuration = OpenAIConfiguration.ollama(host: settings.host, port: settings.port)
            .ollama(settings.toConduit())
        let provider = OpenAIProvider(configuration: configuration)
        let modelID = OpenAIModelID.ollama(model)
        let bridge = ConduitInferenceProvider(provider: provider, model: modelID)
        return .provider(bridge)
    }
}

// MARK: - Dot-syntax Entry Points

/// Enables dot-syntax on `any InferenceProvider` parameters, e.g.:
/// ```swift
/// let agent = try Agent("...", provider: .anthropic(apiKey: "key"))
/// ```
public extension InferenceProvider where Self == ConduitProviderSelection {
    static func anthropic(apiKey: String, model: String = "claude-sonnet-4-5") -> ConduitProviderSelection {
        ConduitProviderSelection.anthropic(apiKey: apiKey, model: model)
    }

    static func openAI(apiKey: String, model: String = "gpt-4o") -> ConduitProviderSelection {
        ConduitProviderSelection.openAI(apiKey: apiKey, model: model)
    }

    static func openRouter(
        apiKey: String,
        model: String
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.openRouter(apiKey: apiKey, model: model)
    }

    static func openRouter(
        apiKey: String,
        model: String,
        configure: (inout OpenRouterRouting) -> Void
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.openRouter(apiKey: apiKey, model: model, configure: configure)
    }

    static func ollama(model: String) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model)
    }

    static func ollama(
        model: String,
        configure: (inout OllamaSettings) -> Void
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model, configure: configure)
    }

    static func ollama(
        model: String,
        baseURL: String
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.ollama(model: model, baseURL: baseURL)
    }

    static func gemini(
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) -> ConduitProviderSelection {
        ConduitProviderSelection.gemini(apiKey: apiKey, model: model)
    }
}

// MARK: - Tool-call streaming forwarding

extension ConduitProviderSelection: ToolCallStreamingInferenceProvider {
    public func streamWithToolCalls(
        prompt: String,
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamUpdate, Error> {
        guard let streamingProvider = makeProvider() as? any ToolCallStreamingInferenceProvider else {
            return StreamHelper.makeTrackedStream { continuation in
                continuation.finish(throwing: AgentError.generationFailed(
                    reason: "Underlying provider does not support tool-call streaming"
                ))
            }
        }

        return streamingProvider.streamWithToolCalls(prompt: prompt, tools: tools, options: options)
    }
}
