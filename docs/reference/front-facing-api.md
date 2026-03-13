# Front-Facing API Reference

This document describes the V3 public API surface of Swarm.

## 1) Entry point and global configuration

```swift
import Swarm

public enum Swarm {
    public static let version: String
    public static let minimumMacOSVersion: String
    public static let minimumiOSVersion: String
}

await Swarm.configure(provider: some InferenceProvider)
await Swarm.configure(cloudProvider: some InferenceProvider)
await Swarm.reset()

let defaultProvider = await Swarm.defaultProvider
let cloudProvider = await Swarm.cloudProvider
```

## 2) Core runtime protocol

```swift
public protocol AgentRuntime: Sendable {
    var name: String { get }
    var tools: [any AnyJSONTool] { get }
    var instructions: String { get }
    var configuration: AgentConfiguration { get }
    var memory: (any Memory)? { get }
    var inferenceProvider: (any InferenceProvider)? { get }
    var tracer: (any Tracer)? { get }
    var handoffs: [AnyHandoffConfiguration] { get }
    var inputGuardrails: [any InputGuardrail] { get }
    var outputGuardrails: [any OutputGuardrail] { get }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult
    nonisolated func stream(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) -> AsyncThrowingStream<AgentEvent, Error>

    func cancel() async
}
```

Convenience extensions:

```swift
run(_ input: String, observer: (any AgentObserver)? = nil)
stream(_ input: String, observer: (any AgentObserver)? = nil)
observed(by: some AgentObserver) -> some AgentRuntime
environment(_ keyPath:, _ value:) -> EnvironmentAgent
```

## 3) Agent (struct, primary init)

The concrete agent type. Creates an immutable configuration; execution state lives in `run()`.

```swift
public struct Agent: AgentRuntime
```

### Canonical initializer

```swift
try Agent(
    tools: [any AnyJSONTool] = [],
    instructions: String = "",
    configuration: AgentConfiguration = .default,
    memory: (any Memory)? = nil,
    inferenceProvider: (any InferenceProvider)? = nil,
    tracer: (any Tracer)? = nil,
    inputGuardrails: [any InputGuardrail] = [],
    outputGuardrails: [any OutputGuardrail] = [],
    guardrailRunnerConfiguration: GuardrailRunnerConfiguration = .default,
    handoffs: [AnyHandoffConfiguration] = []
)
```

### Provider-first convenience

```swift
try Agent(
    _ inferenceProvider: any InferenceProvider,
    tools: [any AnyJSONTool] = [],
    instructions: String = "",
    ...
)
```

### Handoff-agents convenience

```swift
try Agent(
    tools: [any AnyJSONTool] = [],
    instructions: String = "",
    ...,
    handoffAgents: [any AgentRuntime]
)
```

## 4) AgentV3 (modifier chain)

Fluent modifier-chain API for building agents inline. Takes a system prompt and a `@ToolBuilder` trailing closure for tools.

```swift
public struct AgentV3: AgentRuntime
```

### Construction

```swift
AgentV3("You are a helpful assistant.") {
    WeatherTool()
    CalculatorTool()
}
.named("Assistant")
.provider(.anthropic(key: "sk-..."))
.memory(.conversation(limit: 50))
.guardrails(.maxInput(5000), .inputNotEmpty)
```

### Modifiers

| Modifier | Purpose |
|----------|---------|
| `.named(_ name: String)` | Set agent name |
| `.provider(_ provider: some InferenceProvider)` | Set inference provider |
| `.memory(_ memory: MemoryOption)` | Attach memory strategy |
| `.guardrails(_ specs: GuardrailSpec...)` | Add input/output guardrails |
| `.handoffs(_ agents: any AgentRuntime...)` | Add handoff targets |
| `.tracer(_ tracer: some Tracer)` | Attach tracer |
| `.configuration(_ config: AgentConfiguration)` | Override configuration |

## 5) ToolV3 and InlineTool

### `@Tool` macro (recommended)

```swift
@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String { "182.50" }
}
```

### `InlineTool` (closure shorthand)

```swift
InlineTool("reverse", "Reverses a string") { (s: String) in
    String(s.reversed())
}
```

### `@ToolBuilder` result builder

Used as the trailing closure in `AgentV3`. No brackets, no commas:

```swift
AgentV3("instructions") {
    PriceTool()
    InlineTool("greet", "Greets user") { (name: String) in "Hello, \(name)!" }
}
```

## 6) ConversationV3

Stateful multi-turn conversation wrapper.

```swift
public actor ConversationV3 {
    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable { case user, assistant }
        public let role: Role
        public let text: String
    }

    public init(with agent: some AgentRuntime, session: (any Session)? = nil)
    public var messages: [Message] { get }

    @discardableResult
    public func send(_ input: String) async throws -> AgentResult

    public nonisolated func stream(_ input: String) -> AsyncThrowingStream<AgentEvent, Error>

    @discardableResult
    public func streamText(_ input: String) async throws -> String
}
```

## 7) WorkflowV3

Fluent multi-agent pipeline composition.

```swift
public struct WorkflowV3 {
    public enum MergeStrategy {
        case structured
        case first
        case custom(@Sendable ([AgentResult]) -> String)
    }

    public init()

    // Composition
    public func step(_ agent: some AgentRuntime) -> WorkflowV3
    public func parallel(_ agents: [any AgentRuntime], merge: MergeStrategy = .structured) -> WorkflowV3
    public func route(_ condition: @escaping @Sendable (String) -> (any AgentRuntime)?) -> WorkflowV3
    public func repeatUntil(maxIterations: Int = 100, _ condition: @escaping @Sendable (AgentResult) -> Bool) -> WorkflowV3
    public func timeout(_ duration: Duration) -> WorkflowV3
    public func observed(by observer: some AgentObserver) -> WorkflowV3

    // Execution
    public func run(input: String) async throws -> AgentResult
    public func stream(input: String) -> AsyncThrowingStream<AgentEvent, Error>

    // Advanced features
    public var advanced: Advanced { get }
}
```

### Advanced namespace

```swift
public extension WorkflowV3 {
    struct Advanced {
        enum CheckpointPolicy { case endOnly, everyStep }

        func checkpoint(id: String, policy: CheckpointPolicy = .endOnly) -> WorkflowV3
        func checkpointStore(_ checkpointing: WorkflowCheckpointing) -> WorkflowV3
        func fallback(primary: some AgentRuntime, to backup: some AgentRuntime, retries: Int = 0) -> WorkflowV3
        func run(_ input: String, resumeFrom checkpointID: String? = nil) async throws -> AgentResult
    }
}

WorkflowCheckpointing.inMemory()
WorkflowCheckpointing.fileSystem(directory: URL)
```

## 8) GuardrailSpec

Concrete guardrail descriptors with static factories. Used with the `.guardrails()` modifier on `AgentV3`.

```swift
public struct GuardrailSpec: Sendable {
    // Input guardrails
    public static func maxInput(_ length: Int) -> GuardrailSpec
    public static var inputNotEmpty: GuardrailSpec

    // Output guardrails
    public static func maxOutput(_ length: Int) -> GuardrailSpec
    public static var outputNotEmpty: GuardrailSpec

    // Custom guardrails
    public static func customInput(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> GuardrailSpec
    public static func customOutput(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> GuardrailSpec
}
```

### Guardrail protocols (for advanced use)

```swift
public protocol InputGuardrail: Sendable {
    func validate(input: String) async throws -> GuardrailResult
}

public protocol OutputGuardrail: Sendable {
    func validate(output: String) async throws -> GuardrailResult
}
```

## 9) RunOptions

```swift
public struct RunOptions: Sendable {
    public var maxIterations: Int
    public var parallelToolCalls: Bool
    public var modelSettings: ModelSettings?

    public static let `default`: RunOptions
}
```

## 10) MemoryOption

Dot-syntax memory factories used with the `.memory()` modifier.

```swift
public struct MemoryOption {
    public static func conversation(limit: Int = 100) -> MemoryOption
    public static func vector(embeddingProvider: some EmbeddingProvider, threshold: Double = 0.75) -> MemoryOption
    public static func slidingWindow(count: Int) -> MemoryOption
    public static func summary(summarizer: some Summarizer) -> MemoryOption
}
```

## 11) HandoffTool

Agents passed to `.handoffs()` are automatically wrapped as tool calls. The LLM can invoke them to delegate control.

```swift
// Via AgentV3 modifier
AgentV3("Route requests to the right specialist.") {
    // tools
}
.handoffs(billingAgent, supportAgent, salesAgent)

// Via Agent init
try Agent(
    instructions: "Route requests.",
    handoffAgents: [billingAgent, supportAgent, salesAgent]
)
```

## 12) Inference providers

```swift
public protocol InferenceProvider: Sendable {
    func generate(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) async throws -> InferenceResponse
}

public protocol InferenceStreamingProvider: InferenceProvider {
    func stream(
        messages: [InferenceMessage],
        tools: [ToolSchema],
        options: InferenceOptions
    ) -> AsyncThrowingStream<InferenceStreamEvent, Error>
}
```

### Provider factories (dot-syntax)

```swift
.anthropic(key: "sk-...")
.openAI(key: "sk-...")
.ollama(model: "llama3")
.foundationModels       // On-device, iOS 26 / macOS 26
```

## 13) Events and results

```swift
public enum AgentEvent: Sendable {
    case started(input: String)
    case completed(result: AgentResult)
    case failed(error: AgentError)
    case cancelled
    case outputToken(token: String)
    case outputChunk(chunk: String)
    case toolCallStarted(call: ToolCall)
    case toolCallCompleted(call: ToolCall, result: ToolResult)
    case handoffStarted(from: String, to: String, input: String)
    case handoffCompleted(from: String, to: String)
    // ... and more
}

public struct AgentResult: Sendable {
    public let output: String
    public let toolCalls: [ToolCall]
    public let toolResults: [ToolResult]
    public let iterationCount: Int
    public let duration: Duration
    public let tokenUsage: TokenUsage?
}
```

## 14) Public macros

| Macro | Applied To | Effect |
|-------|-----------|--------|
| `@Tool("description")` | `struct` | Synthesizes `AnyJSONTool` conformance + JSON schema from `@Parameter` properties |
| `@Parameter("description")` | `var` inside `@Tool` struct | Marks property as a schema parameter with description |
| `@Traceable` | `struct` conforming to `AnyJSONTool` | Injects tracing around `execute()` |
| `#Prompt(...)` | call site | Type-safe interpolated prompt string |

## 15) Naming guarantees

- Observer APIs use the `observer` label.
- Handoff callback naming is `onTransfer` / `transform` / `when`.
- Every public type conforms to `Sendable`.
- Agent is a struct (value type). Execution state lives in `run()`.
- `WorkflowV3` is the single coordination primitive.
- No legacy types: `AgentBuilder`, `AnyAgent`, `AnyTool`, `ClosureInputGuardrail`, `ClosureOutputGuardrail`, `AgentBlueprint`, `AgentLoop`.
