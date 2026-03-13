# Swarm Framework -- V3 Public API Catalog

> V3 API surface: ~45 public types.
> Authoritative design spec: `docs/reference/front-facing-api.md`
> Last updated: 2026-03-13

---

## Table of Contents

1. [Entry Point & Global Configuration](#1-entry-point--global-configuration)
2. [Core Runtime Protocol](#2-core-runtime-protocol)
3. [Agent (Struct Init)](#3-agent-struct-init)
4. [AgentV3 (Modifier Chain)](#4-agentv3-modifier-chain)
5. [ConversationV3](#5-conversationv3)
6. [WorkflowV3](#6-workflowv3)
7. [Tooling API](#7-tooling-api)
8. [Guardrails API](#8-guardrails-api)
9. [Memory & Sessions](#9-memory--sessions)
10. [Handoffs](#10-handoffs)
11. [Observability](#11-observability)
12. [Inference & Model Controls](#12-inference--model-controls)
13. [Core Value / Event / Error Types](#13-core-value--event--error-types)
14. [Public Macros](#14-public-macros)
15. [Resilience Primitives](#15-resilience-primitives)
16. [Inference Providers](#16-inference-providers)
17. [MCP Integration](#17-mcp-integration)
18. [Hive Runtime Integration](#18-hive-runtime-integration)
19. [Naming Guarantees & Design Invariants](#19-naming-guarantees--design-invariants)

---

## 1. Entry Point & Global Configuration

**File**: `Sources/Swarm/Swarm.swift`

```swift
import Swarm

public enum Swarm {
    public static let version: String
    public static let minimumMacOSVersion: String
    public static let minimumiOSVersion: String

    public static func configure(provider: some InferenceProvider) async
    public static func configure(cloudProvider: some InferenceProvider) async
    public static func reset() async

    public static var defaultProvider: (any InferenceProvider)? { get async }
    public static var cloudProvider: (any InferenceProvider)? { get async }
}
```

---

## 2. Core Runtime Protocol

**File**: `Sources/Swarm/Core/AgentRuntime.swift`

### `AgentRuntime`

The central protocol. Both `Agent` and `AgentV3` conform to this.

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

**Convenience extensions**:

```swift
func run(_ input: String, observer: (any AgentObserver)? = nil) async throws -> AgentResult
func stream(_ input: String, observer: (any AgentObserver)? = nil) -> AsyncThrowingStream<AgentEvent, Error>
func observed(by observer: some AgentObserver) -> some AgentRuntime
func environment<V: Sendable>(_ keyPath: WritableKeyPath<AgentEnvironment, V>, _ value: V) -> EnvironmentAgent
```

### `AgentConfiguration`

```swift
public struct AgentConfiguration: Sendable {
    public var name: String
    public var maxIterations: Int
    public var parallelToolCalls: Bool
    public var modelSettings: ModelSettings?
    public var runtimeMode: SwarmRuntimeMode

    public static let `default`: AgentConfiguration
}
```

### `InferenceProvider`

```swift
public protocol InferenceProvider: Sendable {
    func generate(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse
}

public protocol InferenceStreamingProvider: InferenceProvider {
    func stream(messages: [InferenceMessage], tools: [ToolSchema], options: InferenceOptions) -> AsyncThrowingStream<InferenceStreamEvent, Error>
}
```

---

## 3. Agent (Struct Init)

**File**: `Sources/Swarm/Agents/Agent.swift`

```swift
public struct Agent: AgentRuntime
```

### Initializers

```swift
// Canonical: all parameters explicit
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

// Provider-first convenience
try Agent(_ inferenceProvider: any InferenceProvider, tools: ..., instructions: ..., ...)

// Handoff-agents convenience
try Agent(tools: ..., instructions: ..., ..., handoffAgents: [any AgentRuntime])
```

### Example

```swift
let agent = try Agent(
    tools: [WeatherTool(), CalculatorTool()],
    instructions: "You are a helpful assistant with access to tools.",
    inferenceProvider: .anthropic(key: "sk-...")
)

let result = try await agent.run("What's the weather in Tokyo?")
```

---

## 4. AgentV3 (Modifier Chain)

Inline-first, fluent modifier-chain API. Takes a system prompt and a `@ToolBuilder` trailing closure.

```swift
public struct AgentV3: AgentRuntime
```

### Construction

```swift
let agent = AgentV3("You are a helpful assistant.") {
    WeatherTool()
    CalculatorTool()
    InlineTool("reverse", "Reverses a string") { (s: String) in
        String(s.reversed())
    }
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
| `.guardrails(_ specs: GuardrailSpec...)` | Add guardrails |
| `.handoffs(_ agents: any AgentRuntime...)` | Add handoff targets |
| `.tracer(_ tracer: some Tracer)` | Attach tracer |
| `.configuration(_ config: AgentConfiguration)` | Override configuration |

---

## 5. ConversationV3

**File**: `Sources/Swarm/Core/Conversation.swift`

Stateful multi-turn conversation wrapper around any `AgentRuntime`.

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

### Example

```swift
let agent = AgentV3("You answer Swift questions.") {
    // tools
}
.provider(.anthropic(key: "sk-..."))

let chat = ConversationV3(with: agent)
try await chat.send("What is a protocol?")
try await chat.send("Can you give an example?")
```

---

## 6. WorkflowV3

**File**: `Sources/Swarm/Workflow/Workflow.swift`

Fluent multi-agent pipeline composition. The single preferred coordination primitive.

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

    // Advanced
    public var advanced: Advanced { get }
}

public extension WorkflowV3 {
    struct Advanced {
        public enum CheckpointPolicy { case endOnly, everyStep }

        public func checkpoint(id: String, policy: CheckpointPolicy = .endOnly) -> WorkflowV3
        public func checkpointStore(_ checkpointing: WorkflowCheckpointing) -> WorkflowV3
        public func fallback(primary: some AgentRuntime, to backup: some AgentRuntime, retries: Int = 0) -> WorkflowV3
        public func run(_ input: String, resumeFrom checkpointID: String? = nil) async throws -> AgentResult
    }
}

public struct WorkflowCheckpointing: Sendable {
    public static func inMemory() -> WorkflowCheckpointing
    public static func fileSystem(directory: URL) -> WorkflowCheckpointing
}
```

### Example

```swift
let result = try await WorkflowV3()
    .step(researchAgent)
    .step(writerAgent)
    .run(input: "Write about Swift concurrency.")
```

---

## 7. Tooling API

**Files**: `Sources/Swarm/Tools/`

### `@Tool` macro

```swift
@Tool("Searches the web for information")
struct WebSearchTool {
    @Parameter("The search query") var query: String
    @Parameter("Max results") var limit: Int = 5

    func execute() async throws -> String { ... }
}
```

### `InlineTool`

Closure-based tool for one-off use in `@ToolBuilder` blocks:

```swift
InlineTool("reverse", "Reverses a string") { (s: String) in
    String(s.reversed())
}
```

### `@ToolBuilder`

Result builder for the trailing closure on `AgentV3`. No brackets, no commas:

```swift
AgentV3("instructions") {
    PriceTool()
    WeatherTool()
    InlineTool("greet", "Greets") { (name: String) in "Hello, \(name)!" }
}
```

### Supporting types

| Type | Kind | Purpose |
|------|------|---------|
| `ToolSchema` | struct | JSON Schema descriptor derived from `@Tool` |
| `ToolParameter` | struct | Individual parameter descriptor |
| `FunctionTool` | struct | Closure-based tool (low-level) |
| `ToolRegistry` | actor | Mutable registry of tools; lookup by name |
| `ParallelToolExecutor` | actor | Runs multiple tool calls concurrently |

---

## 8. Guardrails API

**Files**: `Sources/Swarm/Guardrails/`

### `GuardrailSpec` (V3 factories)

```swift
public struct GuardrailSpec: Sendable {
    public static func maxInput(_ length: Int) -> GuardrailSpec
    public static var inputNotEmpty: GuardrailSpec
    public static func maxOutput(_ length: Int) -> GuardrailSpec
    public static var outputNotEmpty: GuardrailSpec
    public static func customInput(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> GuardrailSpec
    public static func customOutput(_ name: String, _ validate: @escaping @Sendable (String) async throws -> GuardrailResult) -> GuardrailSpec
}
```

### Protocols (advanced)

```swift
public protocol InputGuardrail: Sendable {
    func validate(input: String) async throws -> GuardrailResult
}

public protocol OutputGuardrail: Sendable {
    func validate(output: String) async throws -> GuardrailResult
}
```

### Result types

```swift
public struct GuardrailResult: Sendable {
    public enum Outcome: Sendable { case pass, block(reason: String), modify(String) }
    public let outcome: Outcome
}

public enum GuardrailError: Error {
    case inputBlocked(reason: String)
    case outputBlocked(reason: String)
    case toolInputBlocked(tool: String, reason: String)
    case toolOutputBlocked(tool: String, reason: String)
}
```

---

## 9. Memory & Sessions

**Files**: `Sources/Swarm/Memory/`

### `MemoryOption` (V3 factories)

```swift
public struct MemoryOption {
    public static func conversation(limit: Int = 100) -> MemoryOption
    public static func vector(embeddingProvider: some EmbeddingProvider, threshold: Double = 0.75) -> MemoryOption
    public static func slidingWindow(count: Int) -> MemoryOption
    public static func summary(summarizer: some Summarizer) -> MemoryOption
}
```

### Core protocols

```swift
public protocol Memory: Actor, Sendable {
    var count: Int { get }
    var isEmpty: Bool { get }
    func add(_ message: MemoryMessage) async
    func context(for query: String, tokenLimit: Int) async -> String
    func allMessages() async -> [MemoryMessage]
    func clear() async
}

public protocol Session: Sendable {
    var id: String { get }
    var messages: [MemoryMessage] { get async }
    func add(_ message: MemoryMessage) async
    func clear() async
}
```

### Concrete implementations

| Type | Description |
|------|-------------|
| `ConversationMemory` | Token-limited rolling buffer |
| `SlidingWindowMemory` | Fixed message count window |
| `SummaryMemory` | LLM-compressed conversation history |
| `VectorMemory` | SIMD cosine-similarity semantic search (via Accelerate) |
| `HybridMemory` | Combines multiple memory strategies |
| `PersistentMemory` | SwiftData-backed durable storage |
| `InMemorySession` | In-process session implementation |

---

## 10. Handoffs

**Files**: `Sources/Swarm/Core/Handoff/`

Handoffs are injected as tool calls. When the LLM selects a handoff tool, the current agent delegates to the target.

### V3 usage

```swift
// Pass agents directly
AgentV3("Route requests to the right specialist.") { ... }
    .handoffs(billingAgent, supportAgent, salesAgent)

// Or via Agent init
try Agent(instructions: "Route.", handoffAgents: [billingAgent, supportAgent])
```

### Supporting types

| Type | Kind | Purpose |
|------|------|---------|
| `AnyHandoffConfiguration` | struct | Type-erased handoff config |
| `HandoffHistory` | enum | `.none` / `.full` / `.summary` |
| `HandoffPolicy` | enum | Routing/delegation policy |

---

## 11. Observability

**Files**: `Sources/Swarm/Observability/`, `Sources/Swarm/Core/RunHooks.swift`

### `AgentObserver`

```swift
public protocol AgentObserver: Sendable {
    func agentDidStart(name: String, input: String) async
    func agentDidComplete(name: String, result: AgentResult) async
    func agentDidFail(name: String, error: Error) async
    func toolWillCall(name: String, arguments: SendableValue) async
    func toolDidReturn(name: String, result: SendableValue) async
    func handoffDidOccur(from: String, to: String) async
}
```

### `Tracer`

```swift
public protocol Tracer: Actor, Sendable {
    func startSpan(_ name: String, metadata: [String: SendableValue]) -> TraceSpan
    func emit(_ event: TraceEvent) async
    func flush() async
}
```

### Concrete tracers

| Type | Description |
|------|-------------|
| `ConsoleTracer` | Prints events to stdout |
| `PrettyConsoleTracer` | Formatted, human-readable console output |
| `SwiftLogTracer` | Forwards events to `swift-log` |
| `CompositeTracer` | Fan-out to multiple tracers |
| `NoOpTracer` | Discards all events |
| `BufferedTracer` | Stores events in memory |

---

## 12. Inference & Model Controls

```swift
public struct InferenceOptions: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var stopSequences: [String]
    public var model: String?
    public var toolChoice: ToolChoice
    public var stream: Bool

    public static let `default`: InferenceOptions
}

public struct ModelSettings: Sendable {
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var parallelToolCalls: Bool?

    public static let `default`: ModelSettings
}

public enum ToolChoice: Sendable {
    case auto, required, none, specific(name: String)
}
```

---

## 13. Core Value / Event / Error Types

### Results

```swift
public struct AgentResult: Sendable {
    public let output: String
    public let toolCalls: [ToolCall]
    public let toolResults: [ToolResult]
    public let iterationCount: Int
    public let duration: Duration
    public let tokenUsage: TokenUsage?
    public let metadata: [String: SendableValue]
}

public struct TokenUsage: Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public var totalTokens: Int { inputTokens + outputTokens }
}
```

### Events

```swift
public enum AgentEvent: Sendable {
    case started(input: String)
    case completed(result: AgentResult)
    case failed(error: AgentError)
    case cancelled
    case thinking(thought: String)
    case toolCallStarted(call: ToolCall)
    case toolCallCompleted(call: ToolCall, result: ToolResult)
    case toolCallFailed(call: ToolCall, error: AgentError)
    case outputToken(token: String)
    case outputChunk(chunk: String)
    case iterationStarted(number: Int)
    case iterationCompleted(number: Int)
    case handoffStarted(from: String, to: String, input: String)
    case handoffCompleted(from: String, to: String)
    case guardrailStarted(name: String, type: GuardrailType)
    case guardrailPassed(name: String, type: GuardrailType)
    case guardrailTriggered(name: String, type: GuardrailType, message: String?)
    case memoryAccessed(operation: MemoryOperation, count: Int)
    case llmStarted(model: String?, promptTokens: Int?)
    case llmCompleted(model: String?, promptTokens: Int?, completionTokens: Int?, duration: TimeInterval)
}
```

### Universal data carrier

```swift
public enum SendableValue: Sendable, Codable, Equatable {
    case null, bool(Bool), int(Int), double(Double), string(String)
    case array([SendableValue]), dictionary([String: SendableValue])
}
```

### Errors

```swift
public enum AgentError: Error, Sendable {
    case inferenceProviderUnavailable
    case generationFailed(underlying: Error)
    case invalidToolArguments(tool: String, reason: String)
    case toolExecutionFailed(tool: String, underlying: Error)
    case toolNotFound(name: String)
    case maxIterationsExceeded(limit: Int)
    case guardrailViolation(GuardrailError)
    case handoffFailed(target: String, reason: String)
    case cancelled
    case timeout(after: Duration)
    // ...
}

public enum WorkflowError: Error, Sendable {
    case noSteps
    case stepFailed(index: Int, underlying: Error)
    case timeout(after: Duration)
    case cancelled
    case checkpointNotFound(id: String)
}
```

---

## 14. Public Macros

| Macro | Applied To | Effect |
|-------|-----------|--------|
| `@Tool("description")` | `struct` | Synthesizes `AnyJSONTool` conformance + JSON schema from `@Parameter` properties |
| `@Parameter("description")` | `var` inside `@Tool` struct | Marks property as a schema parameter |
| `@Traceable` | `struct` conforming to `AnyJSONTool` | Injects tracing around `execute()` |
| `#Prompt(...)` | call site | Type-safe interpolated prompt string |

---

## 15. Resilience Primitives

```swift
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var backoffStrategy: BackoffStrategy
}

public enum BackoffStrategy: Sendable {
    case constant(Duration)
    case linear(Duration)
    case exponential(Duration, base: Double = 2.0)
    case fibonacci(Duration)
}

public actor CircuitBreaker {
    public enum State { case closed, open, halfOpen }
    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T
    public func reset() async
}

public actor RateLimiter {
    public init(requestsPerSecond: Double, burst: Int)
    public func acquire() async throws
}
```

---

## 16. Inference Providers

```swift
// Dot-syntax factories for provider configuration
.anthropic(key: "sk-...")
.openAI(key: "sk-...")
.ollama(model: "llama3")
.foundationModels

// Multi-provider routing
public actor MultiProvider: InferenceProvider {
    public init(providers: [String: any InferenceProvider], default: any InferenceProvider)
}
```

---

## 17. MCP Integration

### Swarm as MCP Client

```swift
public actor MCPClient {
    public init(serverURL: URL)
    public func connect() async throws
    public func disconnect() async
    public func listTools() async throws -> [ToolSchema]
    public func callTool(name: String, arguments: SendableValue) async throws -> SendableValue
}
```

### Swarm as MCP Server

```swift
public actor SwarmMCPServerService {
    public init(tools: [any AnyJSONTool])
    public func start() async throws
    public func stop() async
    public func listTools() async -> [ToolSchema]
    public func callTool(name: String, arguments: SendableValue) async throws -> SendableValue
}
```

---

## 18. Hive Runtime Integration

**Files**: `Sources/Swarm/HiveSwarm/`

The Hive bridge for DAG-compiled workflows with checkpointing and deterministic retry.

| Type | Kind | Purpose |
|------|------|---------|
| `GraphAgent` | struct | Hive-backed agent node for DAG orchestration |
| `RetryPolicyBridge` | enum | Converts `RetryPolicy` to Hive retry config |
| `WorkflowCheckpointing` | struct | Checkpoint store configuration |

---

## 19. Naming Guarantees & Design Invariants

| Invariant | Detail |
|-----------|--------|
| **Agent is a struct** | Immutable config, execution state in `run()` |
| **`observer` label** | All observer parameters use `observer:` |
| **`Sendable` everywhere** | Every public type conforms to `Sendable` |
| **No legacy types** | `AgentBuilder`, `AnyAgent`, `AnyTool`, `ClosureInputGuardrail`, `ClosureOutputGuardrail`, `AgentBlueprint`, `AgentLoop`, `ReActAgent`, `PlanAndExecuteAgent` are removed |
| **`WorkflowV3` is the single primitive** | No parallel `Orchestration` in the public API |
| **Strict concurrency** | `StrictConcurrency` enabled on all targets |
| **No `print()` in production** | All logging goes through `swift-log` (`Log.*`) |

---

## Quick-Reference Summary

| Subsystem | Key Entry Points |
|-----------|----------------|
| **Setup** | `Swarm.configure(provider:)` |
| **Agent (struct)** | `Agent(tools:instructions:inferenceProvider:)` |
| **Agent (modifier chain)** | `AgentV3("instructions") { tools }.provider(...)` |
| **Conversation** | `ConversationV3(with: agent)` |
| **Workflow** | `WorkflowV3().step(...).run(input:)` |
| **Tools** | `@Tool`, `@Parameter`, `InlineTool`, `@ToolBuilder` |
| **Guardrails** | `GuardrailSpec.maxInput(...)`, `.inputNotEmpty` |
| **Memory** | `MemoryOption.conversation(limit:)`, `.vector(...)` |
| **Handoffs** | `.handoffs(agent1, agent2)` |
| **Observability** | `AgentObserver`, `Tracer` |
| **Providers** | `.anthropic(key:)`, `.openAI(key:)`, `.ollama()`, `.foundationModels` |
| **MCP** | `MCPClient`, `SwarmMCPServerService` |
