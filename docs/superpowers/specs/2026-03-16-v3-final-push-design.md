# V3 API Redesign — Final Push

**Date:** 2026-03-16
**Status:** Approved (v2 — post spec review fixes)
**Goal:** Complete the remaining ~15% of V3 API redesign — seal AnyJSONTool, add `#Tool` macro, reduce public type count, validate with AI agent eval.

---

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| AnyJSONTool seal | Full internal via `ToolCollection` opaque wrapper | `ToolBuilder` builds `ToolCollection`, AnyJSONTool never in public signatures |
| Inline tools | `#Tool` freestanding expression macro | Compile-time param extraction from closure labels |
| Type reduction | Delete type-erasers, keep concrete public, factory-first | `where Self ==` requires public concrete types |
| Agent init | `init(_:provider:tools:)` + modifier chain | Progressive disclosure, one obvious path |
| Optional subsystems | `some` for singles, `any` for optional/arrays | Swift type system constraint |
| Config vs runtime | Modifiers set defaults, `run()` accepts overrides | Memory/tracer are execution concerns |
| Memory protocol | Remove `Actor` inheritance, use `Sendable` + `async` methods | Allows struct Agent to store `any Memory` cleanly |
| Tool protocol | Keep existing contract (instance props, `Input`/`Output` associated types) | No gratuitous redesign of working protocol |

---

## 1. Agent — Core Public Surface

### Init + Modifiers

```swift
public struct Agent: AgentRuntime, Sendable {
    // Internal storage
    internal var _instructions: String
    internal var _provider: any InferenceProvider
    internal var _memory: (any Memory)?
    internal var _retryPolicy: (any RetryPolicy)?
    internal var _tracer: (any Tracer)?
    internal var _tools: [any AnyJSONTool]           // internal bridge type
    internal var _inputGuardrails: [any InputGuardrail]
    internal var _outputGuardrails: [any OutputGuardrail]
    internal var _handoffs: [any AgentRuntime]
    internal var _configuration: AgentConfiguration

    // ONE init — instructions + provider + tools (trailing closure)
    public init(
        _ instructions: String,
        provider: some InferenceProvider = .default,
        @ToolBuilder tools: () -> ToolCollection = { ToolCollection.empty }
    ) {
        self._instructions = instructions
        self._provider = provider
        self._tools = tools().storage
        // ... sensible defaults for everything else
    }

    // Progressive disclosure via modifiers — returns modified copy
    public func tools(_ tools: [any Tool]) -> Agent
    public func tools(@ToolBuilder _ tools: () -> ToolCollection) -> Agent
    public func memory(_ memory: some Memory) -> Agent
    public func retryPolicy(_ policy: some RetryPolicy) -> Agent
    public func tracer(_ tracer: any Tracer) -> Agent
    public func guardrails(
        input: [any InputGuardrail] = [],
        output: [any OutputGuardrail] = []
    ) -> Agent
    public func handoffs(_ agents: [any AgentRuntime]) -> Agent
    public func configuration(_ config: AgentConfiguration) -> Agent

    // Execution — defaults from modifiers, overrides per-run
    public func run(
        _ input: String,
        session: (any Session)? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> AgentResult

    // Sugar — calls run() with defaults
    public func callAsFunction(_ input: String) async throws -> AgentResult
}
```

### Usage Spectrum

```swift
// Minimal
let agent = Agent("You are helpful")

// Typical
let agent = Agent("You are helpful", provider: .anthropic(apiKey: key)) {
    WeatherTool()
    SearchTool()
}

// Full
let agent = Agent("You are helpful", provider: .anthropic(apiKey: key)) {
    #Tool("greet", "Says hello") { (name: String) in "Hello, \(name)!" }
    WeatherTool()
}
.memory(.slidingWindow(maxTokens: 4000))
.retryPolicy(.exponential(maxRetries: 5))
.tracer(.console())
.guardrails(input: [.notEmpty(), .maxLength(1000)])
.handoffs([triageAgent, researchAgent])

// Execution
let result = try await agent("Hello")                                      // callAsFunction
let result = try await agent.run("Hello", session: mySession)              // with session
```

### Provider Default

The `provider` parameter defaults to `.default`, which resolves via the existing provider resolution chain:
1. Explicit provider passed to init
2. Environment provider (`.environment(\.inferenceProvider, ...)`)
3. `Swarm.defaultProvider` (set via `Swarm.configure(provider:)`)
4. `Swarm.cloudProvider`
5. Apple Foundation Models (if available)
6. Throw `AgentError.inferenceProviderUnavailable`

```swift
extension InferenceProvider where Self == DefaultProviderResolver {
    /// Uses the framework's provider resolution chain.
    public static var `default`: DefaultProviderResolver { .init() }
}
```

---

## 2. AnyJSONTool — Internal Seal via ToolCollection

### Problem

`AnyJSONTool` leaks into 18+ public signatures. Making it `internal` requires a public intermediary type for `@ToolBuilder`'s Component type.

### Solution: `ToolCollection` opaque wrapper

```swift
/// An opaque collection of tools built by `@ToolBuilder`.
///
/// You never create this directly — it's produced by the `@ToolBuilder` result builder
/// and consumed by `Agent` initializers and modifiers.
public struct ToolCollection: Sendable {
    internal let storage: [any AnyJSONTool]

    /// An empty tool collection.
    public static let empty = ToolCollection(storage: [])

    internal init(storage: [any AnyJSONTool]) {
        self.storage = storage
    }
}
```

### AnyJSONTool becomes internal

```swift
// INTERNAL — unchanged contract, just hidden from public API
internal protocol AnyJSONTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    var inputGuardrails: [any ToolInputGuardrail] { get }
    var outputGuardrails: [any ToolOutputGuardrail] { get }
    var isEnabled: Bool { get }
    func execute(arguments: [String: SendableValue]) async throws -> SendableValue
}
```

### Tool protocol — UNCHANGED

The existing `Tool` protocol keeps its current contract. No gratuitous redesign:

```swift
// PUBLIC — existing contract, unchanged
public protocol Tool: Sendable {
    associatedtype Input: Codable & Sendable
    associatedtype Output: Encodable & Sendable

    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    var inputGuardrails: [any ToolInputGuardrail] { get }
    var outputGuardrails: [any ToolOutputGuardrail] { get }

    func execute(_ input: Input) async throws -> Output
}
```

### Bridging via existential opening (Swift 5.7+)

The existing `AnyJSONToolAdapter<T: Tool>` becomes internal and is used via existential opening:

```swift
// INTERNAL — bridges typed Tool to dynamic AnyJSONTool
internal struct AnyJSONToolAdapter<T: Tool>: AnyJSONTool, Sendable {
    let tool: T
    var name: String { tool.name }
    var description: String { tool.description }
    var parameters: [ToolParameter] { tool.parameters }
    // ... same implementation as today

    func execute(arguments: [String: SendableValue]) async throws -> SendableValue {
        let input: T.Input = try SendableValue.dictionary(arguments).decode()
        let output = try await tool.execute(input)
        return try SendableValue(encoding: output)
    }
}

// INTERNAL — opens `any Tool` existential and bridges to AnyJSONTool
internal func bridgeToolToAnyJSON<T: Tool>(_ tool: T) -> any AnyJSONTool {
    AnyJSONToolAdapter(tool)
}
```

Key insight: When you call `bridgeToolToAnyJSON(someTool)` where `someTool` is `any Tool`, Swift 5.7+ **opens the existential** — the compiler infers `T` as the underlying concrete type, even though the call site only has `any Tool`. This is how we bridge without knowing the concrete type at the call site.

### Agent modifier for `[any Tool]`

```swift
extension Agent {
    public func tools(_ tools: [any Tool]) -> Agent {
        var copy = self
        copy._tools = tools.map { bridgeToolToAnyJSON($0) }  // existential opening
        return copy
    }
}
```

### Files Affected (20)

All files currently exposing `AnyJSONTool` in public signatures:
- `Agent.swift` — stored property type, init signatures
- `AgentRuntime.swift` — protocol requirement `var tools: [any AnyJSONTool]`
- `ToolParameterBuilder.swift` — `ToolBuilder` result type → `ToolCollection`
- `ToolBridging.swift` — `AnyJSONToolAdapter` and `asAnyJSONTool()` → internal
- `Tool.swift` — `AnyJSONTool` protocol → internal, `ToolRegistry` public methods
- `AgentTool.swift`, `BuiltInTools.swift`, `FunctionTool.swift` — conformances
- `ObservedAgent.swift`, `EnvironmentAgent.swift` — references
- `MCPClient.swift`, `MCPToolBridge.swift` — MCP bridging
- `ToolGuardrails.swift` — guardrail references
- `HiveSwarm/GraphAgent.swift`, `HiveSwarm/ToolRegistryAdapter.swift` — HiveSwarm
- `MacroDeclarations.swift` — macro declaration (conformance target changes)
- `SwarmMacros/ToolMacro.swift` — generates `AnyJSONTool` conformance → internal bridge
- `SwarmMacros/Plugin.swift` — add `InlineToolMacro.self` to `providingMacros`

### ToolRegistry changes

`ToolRegistry` public methods currently take `[any AnyJSONTool]`. Updated:

```swift
public actor ToolRegistry {
    // Public API uses Tool protocol
    public init(tools: [any Tool]) throws { ... }
    public func register(_ tool: some Tool) throws { ... }
    public func register(_ tools: [any Tool]) throws { ... }

    // Internal storage stays [any AnyJSONTool]
    internal var allTools: [any AnyJSONTool] { ... }

    // Execution stays internal — framework calls this, not users
    public func execute(
        toolNamed name: String,
        arguments: [String: SendableValue],
        agent: (any AgentRuntime)? = nil,
        context: AgentContext? = nil,
        observer: (any AgentObserver)? = nil
    ) async throws -> SendableValue { ... }
}
```

### AgentRuntime protocol update

```swift
public protocol AgentRuntime: Sendable {
    nonisolated var name: String { get }
    nonisolated var instructions: String { get }
    nonisolated var configuration: AgentConfiguration { get }
    nonisolated var memory: (any Memory)? { get }
    nonisolated var inferenceProvider: (any InferenceProvider)? { get }
    nonisolated var tracer: (any Tracer)? { get }
    nonisolated var inputGuardrails: [any InputGuardrail] { get }
    nonisolated var outputGuardrails: [any OutputGuardrail] { get }

    // CHANGED: was `[any AnyJSONTool]` → now `[any Tool]`
    // Internal bridge converts to [any AnyJSONTool] when needed
    nonisolated var tools: [any Tool] { get }

    func run(_ input: String, session: (any Session)?, observer: (any AgentObserver)?) async throws -> AgentResult
}
```

**Round-trip conversion:** Agent stores `[any AnyJSONTool]` internally (for provider dispatch) but exposes `[any Tool]` via `AgentRuntime.tools`. This works because ALL tools now conform to `Tool`:
- `@Tool` macro generates `Tool` conformance
- `#Tool` macro generates `Tool` conformance
- Manual struct tools implement `Tool` directly

The `AnyJSONToolAdapter<T>` stores `let tool: T` where `T: Tool`. To expose `[any Tool]`, Agent maintains a parallel `[any Tool]` array alongside the internal `[any AnyJSONTool]` array, populated at init/modifier time when the concrete types are still available. This avoids any lossy round-trip.

### @Tool macro conformance change

Currently `ToolMacro.swift` line 142 generates:
```swift
extension MyTool: AnyJSONTool, Sendable {}
```

Changed to generate `Tool` conformance (public protocol):
```swift
extension MyTool: Tool, Sendable {}
```

The `@Tool` macro generates a struct conforming to `Tool` (public). The framework bridges it to `AnyJSONTool` internally via `AnyJSONToolAdapter` when the tool enters `ToolBuilder` or `ToolRegistry`. The macro-generated `execute(arguments:)` method is no longer needed on the struct — `AnyJSONToolAdapter.execute(arguments:)` handles the decode/dispatch.

**What the macro generates:**
```swift
// @Tool("Gets weather for a city") generates:
public struct WeatherTool: Tool, Sendable {
    typealias Input = WeatherToolInput
    typealias Output = String

    @Parameter(description: "City name") var location: String

    let name = "weather"
    let description = "Gets weather for a city"
    let parameters: [ToolParameter] = [
        ToolParameter(name: "location", description: "City name", type: .string)
    ]

    // User implements this
    func execute(_ input: WeatherToolInput) async throws -> String { ... }
}

// Also generated — Codable input struct
struct WeatherToolInput: Codable, Sendable {
    let location: String
}
```

**Bridging happens in ToolBuilder/ToolRegistry**, not the macro:
```swift
// ToolBuilder.buildExpression<T: Tool> wraps via AnyJSONToolAdapter
// AnyJSONToolAdapter.execute decodes [String: SendableValue] → T.Input, calls tool.execute
```

This is clean: macros generate public `Tool` conformance, framework handles internal bridging.

---

## 3. `#Tool` Freestanding Expression Macro

### Declaration

```swift
// In MacroDeclarations.swift
@freestanding(expression)
public macro Tool(
    _ name: String,
    _ description: String,
    body: () -> Void   // placeholder — actual closure is parsed by SwiftSyntax
) = #externalMacro(module: "SwarmMacros", type: "InlineToolMacro")
```

Note: `@freestanding(expression)` and `@attached(member/extension)` macros can share the name `Tool` because they use different sigils (`#Tool` vs `@Tool`) and have different parameter counts (2 strings vs 1 string). Swift resolves this unambiguously.

### Expansion

```swift
// User writes:
#Tool("greet", "Says hello") { (name: String, age: Int) in
    "Hello, \(name)! You are \(age)."
}

// Macro expands to:
{
    struct _GreetInput: Codable, Sendable {
        let name: String
        let age: Int
    }
    struct _InlineTool_greet: Tool, Sendable {
        typealias Input = _GreetInput
        typealias Output = String

        let name = "greet"
        let description = "Says hello"
        let parameters: [ToolParameter] = [
            ToolParameter(name: "name", description: "name", type: .string, isRequired: true),
            ToolParameter(name: "age", description: "age", type: .int, isRequired: true)
        ]

        func execute(_ input: _GreetInput) async throws -> String {
            "Hello, \(input.name)! You are \(input.age)."
        }
    }
    return _InlineTool_greet()
}()
```

**Key design choice:** `#Tool` generates `Tool` conformance (public protocol), NOT `AnyJSONTool` (internal). This is critical because `@freestanding(expression)` macros expand at the **call site** (user's module), not inside the Swarm module. The expansion can only reference public types. The macro generates:
1. A `Codable` input struct from the closure parameter labels/types
2. A `Tool`-conforming struct with typed `execute(_ input:)` method
3. The closure body is inlined into `execute`, accessing params via `input.name`, `input.age`, etc.

`ToolBuilder.buildExpression<T: Tool>` handles bridging to internal `AnyJSONTool` automatically.

### Supported Features

- Any number of labeled closure parameters → become `ToolParameter` entries
- Type mapping: `String` → `.string`, `Int` → `.int`, `Double` → `.double`, `Bool` → `.bool`
- Optional parameters (`String?`) → `isRequired: false`
- Parameters with defaults → `isRequired: false` with `defaultValue`
- `async throws` closure body supported
- Return type must be `String` (converted to `.string(result)`)
- Works inside `@ToolBuilder` trailing closures via `buildExpression(_ expression: any AnyJSONTool)`

### Implementation

New file: `SwarmMacros/InlineToolMacro.swift`
- Conforms to `ExpressionMacro`
- Uses SwiftSyntax to parse `ClosureExprSyntax` parameter clause
- Extracts parameter labels and type annotations
- Generates anonymous struct conforming to `AnyJSONTool`
- Inlines the closure body into `execute(arguments:)` with parameter extraction
- Wraps in immediately-invoked closure expression

**Must add to Plugin.swift:**
```swift
let providingMacros: [Macro.Type] = [
    ToolMacro.self,
    ParameterMacro.self,
    AgentMacro.self,
    TraceableMacro.self,
    PromptMacro.self,
    BuilderMacro.self,
    InlineToolMacro.self   // NEW
]
```

---

## 4. ToolBuilder Update

`@ToolBuilder` changes from `[any AnyJSONTool]` to `ToolCollection`:

```swift
@resultBuilder
public struct ToolBuilder {
    public static func buildBlock() -> ToolCollection {
        .empty
    }

    public static func buildBlock(_ components: ToolCollection...) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    // Single AnyJSONTool expression (internal — for framework built-in tools like AgentTool)
    internal static func buildExpression(_ expression: any AnyJSONTool) -> ToolCollection {
        ToolCollection(storage: [expression])
    }

    // Typed Tool expression — bridges via AnyJSONToolAdapter
    public static func buildExpression<T: Tool>(_ expression: T) -> ToolCollection {
        ToolCollection(storage: [AnyJSONToolAdapter(expression)])
    }

    // any Tool expression — uses existential opening
    public static func buildExpression(_ expression: any Tool) -> ToolCollection {
        ToolCollection(storage: [bridgeToolToAnyJSON(expression)])
    }

    // Array of tools
    public static func buildExpression(_ expression: [any Tool]) -> ToolCollection {
        ToolCollection(storage: expression.map { bridgeToolToAnyJSON($0) })
    }

    public static func buildOptional(_ component: ToolCollection?) -> ToolCollection {
        component ?? .empty
    }

    public static func buildEither(first component: ToolCollection) -> ToolCollection {
        component
    }

    public static func buildEither(second component: ToolCollection) -> ToolCollection {
        component
    }

    public static func buildArray(_ components: [ToolCollection]) -> ToolCollection {
        ToolCollection(storage: components.flatMap(\.storage))
    }

    public static func buildLimitedAvailability(_ component: ToolCollection) -> ToolCollection {
        component
    }
}
```

Note: The `buildExpression(any AnyJSONTool)` overload is `internal` — only visible within the Swarm module. This allows framework-internal tools (like `AgentTool` for handoffs) to work inside `@ToolBuilder` blocks. User-facing tools (`@Tool` and `#Tool` macros) generate `Tool` conformance and use the `buildExpression<T: Tool>` overload instead.

---

## 5. Memory Protocol Migration

### Current (Memory: Actor)

```swift
public protocol Memory: Actor, Sendable {
    var count: Int { get async }
    var isEmpty: Bool { get async }
    func add(_ message: MemoryMessage) async
    func context(for query: String, tokenLimit: Int) async -> String
    func allMessages() async -> [MemoryMessage]
    func clear() async
}
```

### New (Memory: Sendable — drop Actor)

```swift
public protocol Memory: Sendable {
    var count: Int { get async }
    var isEmpty: Bool { get async }
    func add(_ message: MemoryMessage) async
    func context(for query: String, tokenLimit: Int) async -> String
    func allMessages() async -> [MemoryMessage]
    func clear() async
}
```

**Migration steps:**
1. Remove `: Actor` from `Memory` protocol
2. All existing memory actors (`ConversationMemory`, `VectorMemory`, etc.) become `final class` with internal `Mutex` for thread safety, or remain as actors (actors implicitly conform to `Sendable` but no longer required by protocol)
3. `AnyMemory` type-erased actor is **deleted** — replaced by `any Memory`
4. Factory methods move from `AnyMemory` extensions to constrained protocol extensions
5. Agent stores `(any Memory)?` — works because `any Memory` is `Sendable`

**Note:** Existing actors CAN still conform to the new protocol. Removing `Actor` from the protocol doesn't break actor conformers — it just doesn't *require* them to be actors. This makes the migration non-breaking for existing implementations.

### Factory Pattern

```swift
// Concrete types stay public actors (or become final classes)
public actor ConversationMemory: Memory { ... }
public actor VectorMemory: Memory { ... }
public actor SlidingWindowMemory: Memory { ... }
public actor PersistentMemory: Memory { ... }

// Dot-syntax factories on protocol
extension Memory where Self == ConversationMemory {
    public static func conversation(maxMessages: Int = 100) -> ConversationMemory { ... }
}
extension Memory where Self == VectorMemory {
    public static func vector(
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float = 0.7,
        maxResults: Int = 10
    ) -> VectorMemory { ... }
}
extension Memory where Self == SlidingWindowMemory {
    public static func slidingWindow(maxTokens: Int = 4000) -> SlidingWindowMemory { ... }
}
extension Memory where Self == PersistentMemory {
    public static func persistent(
        backend: any PersistentMemoryBackend = InMemoryBackend(),
        conversationId: String = UUID().uuidString,
        maxMessages: Int = 0
    ) -> PersistentMemory { ... }
}
```

---

## 6. Subsystem Factory Pattern (Other Subsystems)

### InferenceProvider

```swift
public protocol InferenceProvider: Sendable { ... }

// Existing factories (already in ConduitProviderSelection.swift) — keep as-is
// Add a `.default` factory that uses the resolution chain:
extension InferenceProvider where Self == DefaultProviderResolver {
    public static var `default`: DefaultProviderResolver { .init() }
}
```

### Guardrails

```swift
public protocol InputGuardrail: Sendable { ... }
public protocol OutputGuardrail: Sendable { ... }

public struct InputGuard: InputGuardrail { ... }
public struct OutputGuard: OutputGuardrail { ... }

extension InputGuardrail where Self == InputGuard {
    public static func maxLength(_ n: Int) -> InputGuard { ... }
    public static func notEmpty() -> InputGuard { ... }
    public static func custom(_ name: String, _ check: @Sendable (String) async throws -> GuardrailResult) -> InputGuard { ... }
}
extension OutputGuardrail where Self == OutputGuard {
    public static func maxLength(_ n: Int) -> OutputGuard { ... }
    public static func custom(_ name: String, _ check: @Sendable (String) async throws -> GuardrailResult) -> OutputGuard { ... }
}
```

### Tracer

```swift
public protocol Tracer: Sendable { ... }

extension Tracer where Self == ConsoleTracer {
    public static func console(verbose: Bool = false) -> ConsoleTracer { ... }
}
extension Tracer where Self == SwiftLogTracer {
    public static func swiftLog(label: String = "swarm") -> SwiftLogTracer { ... }
}
```

### RetryPolicy

```swift
public protocol RetryPolicy: Sendable { ... }

extension RetryPolicy where Self == ExponentialBackoff {
    public static func exponential(maxRetries: Int = 3) -> ExponentialBackoff { ... }
}
extension RetryPolicy where Self == LinearBackoff {
    public static func linear(maxRetries: Int = 3, delay: Duration = .seconds(1)) -> LinearBackoff { ... }
}
```

---

## 7. Types to Delete

| Type | Replaced by |
|------|-------------|
| `AnyMemory` | `any Memory` (native Swift existential) + factory extensions on protocol |
| `MemoryBuilder` | `some Memory` + constrained protocol extensions |
| `ClosureInputGuardrail` | `InputGuard.custom()` factory |
| `ClosureOutputGuardrail` | `OutputGuard.custom()` factory |
| `AnyTool` | `any Tool` (native Swift existential) |
| `AnyAgent` | `any AgentRuntime` (native Swift existential) |
| `ParallelComposition` | Already deprecated — delete |
| `AgentSequence` | Already deprecated — delete |
| Deprecated `ChatGraph.start(threadID:input:options:)` | Delete |
| Deprecated `ChatGraph.resume(threadID:interruptID:payload:options:)` | Delete |
| Deprecated `Workflow+Durable.execute(resumeFrom:)` | Delete |
| Deprecated `AgentTracer.parallel` parameter | Delete |
| Old Agent init overloads (5 current → 1 new) | Single canonical init + modifiers |

### SwiftDataMemory

`SwiftDataMemory.swift` exists in the codebase. Decision: **keep** — it's a concrete `PersistentMemoryBackend` implementation, not a `Memory` implementation. Not in the deletion list.

---

## 8. Estimated Final Public Type Count

| Category | Types | Count |
|----------|-------|-------|
| Core | `Agent`, `AgentRuntime`, `AgentError`, `AgentEvent`, `AgentResult`, `AgentConfiguration`, `ToolCollection` | 7 |
| Tools | `Tool` (protocol), `ToolParameter`, `ToolSchema`, `ToolRegistryError` + macros (`@Tool`, `#Tool`, `@Parameter`, `@ToolBuilder`) | 4 types + 4 macros |
| Memory | `Memory` (protocol), `MemoryMessage`, `ConversationMemory`, `VectorMemory`, `SlidingWindowMemory`, `PersistentMemory`, `HybridMemory`, `SummaryMemory` | 8 |
| Guardrails | `InputGuardrail`, `OutputGuardrail`, `InputGuard`, `OutputGuard`, `GuardrailResult`, `GuardrailError` | 6 |
| Providers | `InferenceProvider`, `DefaultProviderResolver`, `ConduitProviderSelection`, `InferenceOptions`, `InferenceResponse`, `LLM` | 6 |
| Observability | `Tracer`, `TraceEvent`, `TraceSpan`, `AgentObserver`, `ConsoleTracer`, `SwiftLogTracer` | 6 |
| Handoffs | `HandoffRequest`, `HandoffResult`, `AnyHandoffConfiguration` | 3 |
| Resilience | `RetryPolicy`, `ExponentialBackoff`, `LinearBackoff`, `CircuitBreaker` | 4 |
| Workflow | `Workflow`, `WorkflowError` | 2 |
| MCP | `MCPClient`, `MCPServer`, `MCPError`, `MCPCapabilities` | 4 |
| Config | `ModelSettings`, `ContextProfile`, `GuardrailRunnerConfiguration` | 3 |
| HiveSwarm | `HiveSwarm`, `ChatGraph`, `GraphNode` | 3 |
| Session/Context | `Session`, `AgentContext` | 2 |
| Errors/Enums | Misc supporting enums | ~8 |
| **Total** | | **~70** |

Down from 197 → **64% reduction**. Each remaining type earns its place.

---

## 9. AI Agent Eval Criteria

After implementation, validate:

1. **Zero-shot creation** — Can an AI agent create a working agent with one prompt, no docs?
2. **Autocomplete path** — Does typing `Agent(` lead to exactly ONE init signature?
3. **Modifier discovery** — Does typing `.` after an Agent show all modifiers?
4. **Tool creation** — Can the agent use both `#Tool` (inline) and `@Tool` (struct) without confusion?
5. **Factory discovery** — Does `.` on `some Memory` show all factory methods?
6. **No AnyJSONTool leakage** — Is `AnyJSONTool` completely invisible in autocomplete/docs?
7. **Simple case simplicity** — Is `Agent("...") { Tool() }` the obvious first thing to try?
8. **callAsFunction** — Does `try await agent("Hello")` work as expected?

Target: **95/100** agent score (measured by success rate across 20 common agent-building prompts).

---

## 10. Migration Notes

- **Breaking change**: `AnyJSONTool` no longer public. Code referencing it must use `Tool` protocol.
- **Breaking change**: `Memory` protocol drops `Actor` inheritance. Existing actor conformers still work (actors are Sendable), but new implementations are no longer required to be actors.
- **Breaking change**: Agent init signature changes. Old multi-param inits removed. Use `Agent("...", provider: ...) { tools }.memory(...).tracer(...)` pattern.
- **Breaking change**: `AnyMemory` deleted. Use `any Memory` or factory methods.
- **Breaking change**: `ToolBuilder` produces `ToolCollection` (not `[any AnyJSONTool]`).
- **Non-breaking**: `callAsFunction` is additive.
- **Non-breaking**: Modifier methods are additive.
- **Deprecation period**: None — pre-1.0 framework, clean break.

---

## 11. Implementation Order

1. **ToolCollection struct** + internal `bridgeToolToAnyJSON` helper
2. **ToolBuilder** → produce `ToolCollection`
3. **AnyJSONTool** → `internal`
4. **AnyJSONToolAdapter** → `internal`
5. **ToolRegistry** → public methods take `[any Tool]`
6. **AgentRuntime protocol** → `tools` becomes `[any Tool]`
7. **Agent struct** → new canonical init + modifiers + `callAsFunction`
8. **Memory protocol** → drop `Actor`, add factory extensions, delete `AnyMemory`
9. **@Tool macro** → generate `Tool` conformance (not `AnyJSONTool`)
10. **#Tool macro** → new `InlineToolMacro` + Plugin.swift registration
11. **Delete deprecated types** (ParallelComposition, AgentSequence, old ChatGraph methods)
12. **Delete type-erasers** (AnyMemory, ClosureInputGuardrail, ClosureOutputGuardrail, etc.)
13. **Guardrail factories** → constrained protocol extensions
14. **Tracer/RetryPolicy factories** → constrained protocol extensions
15. **Update all tests** — V3 test suite + existing tests
16. **AI agent eval** — run 20-prompt validation suite
