# Getting Started

Get a working Swarm agent in under a minute.

## Installation

### Swift Package Manager

Add Swarm to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/christopherkarani/Swarm.git", from: "0.3.4")
],
targets: [
    .target(name: "YourApp", dependencies: ["Swarm"])
]
```

### Xcode

**File → Add Package Dependencies →** `https://github.com/christopherkarani/Swarm.git`

## Your First Agent

### Using `Agent` (struct init)

The primary way to create an agent is with the `Agent` struct initializer:

```swift
import Swarm

// 1. Define a tool — the @Tool macro generates the JSON schema
@Tool("Looks up the current stock price")
struct PriceTool {
    @Parameter("Ticker symbol") var ticker: String

    func execute() async throws -> String { "182.50" }
}

// 2. Create an agent with tools
let agent = try Agent(
    tools: [PriceTool()],
    instructions: "Answer finance questions using real data.",
    inferenceProvider: .anthropic(key: "sk-...")
)

// 3. Run it
let result = try await agent.run("What is AAPL trading at?")
print(result.output) // "Apple (AAPL) is currently trading at $182.50."
```

### Using `AgentV3` (modifier chain)

`AgentV3` provides a fluent modifier-chain API for building agents inline:

```swift
import Swarm

let agent = AgentV3("Answer finance questions using real data.") {
    PriceTool()
    CalculatorTool()
}
.named("Analyst")
.provider(.anthropic(key: "sk-..."))
.memory(.conversation(limit: 50))
.guardrails(.maxInput(5000), .inputNotEmpty)

let result = try await agent.run("What is AAPL trading at?")
print(result.output) // "Apple (AAPL) is currently trading at $182.50."
```

The `AgentV3` init takes a system prompt string and a `@ToolBuilder` trailing closure for tools. Modifiers like `.named()`, `.provider()`, `.memory()`, and `.guardrails()` chain immutably -- each returns a new configured agent.

## Creating Tools

### `@Tool` macro (recommended)

Define a struct with `@Tool` and annotate parameters with `@Parameter`:

```swift
@Tool("Searches the web for information")
struct WebSearchTool {
    @Parameter("The search query") var query: String
    @Parameter("Max results to return") var limit: Int = 5

    func execute() async throws -> String {
        // Your search implementation
        "Results for \(query)"
    }
}
```

### `InlineTool` (one-off closures)

For quick inline tools that do not need a full struct:

```swift
let reverse = InlineTool("reverse", "Reverses a string") { (s: String) in
    String(s.reversed())
}
```

Use `InlineTool` inside a `@ToolBuilder` closure:

```swift
let agent = AgentV3("You are a helpful text utility.") {
    InlineTool("reverse", "Reverses a string") { (s: String) in
        String(s.reversed())
    }
    InlineTool("uppercase", "Uppercases a string") { (s: String) in
        s.uppercased()
    }
}
.provider(.anthropic(key: "sk-..."))
```

## Running Agents

### Single-turn `run()`

Returns an `AgentResult` with the agent's final output, tool call records, token usage, and duration:

```swift
let result = try await agent.run("What is 2 + 2?")
print(result.output)       // "4"
print(result.duration)     // Duration
print(result.tokenUsage)   // TokenUsage(inputTokens:, outputTokens:)
```

### Streaming with `stream()`

Stream `AgentEvent` values in real time -- ideal for live UI:

```swift
for try await event in agent.stream("Tell me about Swift concurrency.") {
    switch event {
    case .outputToken(let token):
        print(token, terminator: "")
    case .toolCallStarted(let call):
        print("\n[tool: \(call.toolName)]")
    case .completed(let result):
        print("\nDone in \(result.duration)")
    default:
        break
    }
}
```

### Multi-turn `Conversation`

`Conversation` wraps an agent for stateful multi-turn chat:

```swift
let conversation = Conversation(with: agent)

let first = try await conversation.send("What is Swift?")
let followUp = try await conversation.send("How does its concurrency model work?")

// Full transcript
for message in await conversation.messages {
    print("\(message.role): \(message.text)")
}
```

## Multi-Agent Workflows

### Sequential pipeline

Compose multi-agent execution with `WorkflowV3`:

```swift
let result = try await WorkflowV3()
    .step(researchAgent)
    .step(analyzeAgent)
    .step(writerAgent)
    .run(input: "Summarize the WWDC session on Swift concurrency.")
```

### Parallel fan-out

Run multiple agents in parallel and merge their results:

```swift
let result = try await WorkflowV3()
    .parallel([bullAgent, bearAgent, analystAgent], merge: .structured)
    .run(input: "Evaluate Apple's Q4 earnings.")
```

### Routing

Route to different agents based on input content:

```swift
let result = try await WorkflowV3()
    .route { input in
        if input.contains("$") { return mathAgent }
        if input.contains("weather") { return weatherAgent }
        return generalAgent
    }
    .run(input: "What is 15% of $240?")
```

### Advanced: checkpoint and resume

For checkpoint/resume and other power features, use the namespaced advanced API:

```swift
let result = try await WorkflowV3()
    .step(fetchAgent)
    .step(analyzeAgent)
    .advanced
    .checkpoint(id: "report-v1", policy: .everyStep)
    .advanced
    .checkpointStore(.fileSystem(directory: checkpointsURL))
    .advanced
    .run("Summarize the WWDC session", resumeFrom: nil)
```

## Choosing a Provider

Swarm supports multiple inference providers. Swap with one line:

```swift
// On-device (private, no network)
.provider(.foundationModels)

// Anthropic
.provider(.anthropic(key: "sk-..."))

// OpenAI
.provider(.openAI(key: "sk-..."))

// Ollama (local)
.provider(.ollama())
```

Or using the `.environment()` modifier on any `AgentRuntime`:

```swift
agent.environment(\.inferenceProvider, .anthropic(key: "sk-..."))
```

## Requirements

| | Minimum |
|---|---|
| Swift | 6.2+ |
| iOS | 26.0+ |
| macOS | 26.0+ |
| Linux | Ubuntu 22.04+ with Swift 6.2 |

::: tip
Foundation Models require iOS 26 / macOS 26. Cloud providers (Anthropic, OpenAI, Ollama) work on any Swift 6.2 platform including Linux.
:::

## Next Steps

- **[Agents](/agents)** -- Agent types, configuration, tool calling
- **[Tools](/tools)** -- `@Tool` macro, `InlineTool`, tool chains
- **Workflow** -- Use `WorkflowV3` for sequential, parallel, and routed execution
- **[Memory](/memory)** -- Conversation, vector, summary, persistent
