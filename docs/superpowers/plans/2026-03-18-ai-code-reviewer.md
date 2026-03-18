# AI Code Reviewer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Swift CLI example app that fans out three specialist Swarm agents in parallel to review a Swift source file, streaming their findings live to the terminal with colored prefixes, then synthesizes a final report.

**Architecture:** Standalone SPM package at `Examples/CodeReviewer/` depending on Swarm via local path. Three specialist agents (`SecurityAgent`, `PerformanceAgent`, `StyleAgent`) run concurrently via `TaskGroup`, each streaming `.output(.token(...))` events. A `SynthesizerAgent` receives all three outputs and produces a final prioritized action list.

**Tech Stack:** Swift 6, Swift Testing, Swarm (local path `../../`), OpenRouter via `LLM.openRouter(key:model:)`, ANSI escape codes for colored output.

---

## File Map

| File | Responsibility |
|---|---|
| `Examples/CodeReviewer/Package.swift` | SPM manifest — depends on Swarm via `../../`, defines executable + test targets |
| `Examples/CodeReviewer/Sources/CodeReviewer/main.swift` | Entry point — parse CLI args, validate inputs, call `Runner.run()` |
| `Examples/CodeReviewer/Sources/CodeReviewer/Runner.swift` | Orchestrates fan-out: reads file, fires 3 parallel tasks, awaits, calls synthesizer |
| `Examples/CodeReviewer/Sources/CodeReviewer/Output/StreamRenderer.swift` | ANSI color constants + unbuffered print with `[Prefix] 🔴` format |
| `Examples/CodeReviewer/Sources/CodeReviewer/Tools/ReadFileTool.swift` | `Tool` conformance — reads a file path and returns its contents |
| `Examples/CodeReviewer/Sources/CodeReviewer/Agents/SecurityAgent.swift` | Factory function returning a configured `Agent` for security analysis |
| `Examples/CodeReviewer/Sources/CodeReviewer/Agents/PerformanceAgent.swift` | Factory function returning a configured `Agent` for performance analysis |
| `Examples/CodeReviewer/Sources/CodeReviewer/Agents/StyleAgent.swift` | Factory function returning a configured `Agent` for style analysis |
| `Examples/CodeReviewer/Sources/CodeReviewer/Agents/SynthesizerAgent.swift` | Factory function returning a configured `Agent` for synthesis, with `InputGuard.notEmpty()` |
| `Examples/CodeReviewer/Tests/CodeReviewerTests/StreamRendererTests.swift` | Tests ANSI prefix formatting |
| `Examples/CodeReviewer/Tests/CodeReviewerTests/ReadFileToolTests.swift` | Tests file I/O using a fixture file |
| `Examples/CodeReviewer/Tests/CodeReviewerTests/AgentInitTests.swift` | Tests all four agents init without throwing |
| `Examples/CodeReviewer/Tests/CodeReviewerTests/RunnerTests.swift` | Tests Runner error paths (missing key, missing file, guardrail trip) |
| `Examples/CodeReviewer/Tests/CodeReviewerTests/Fixtures/Sample.swift` | Sample Swift file used as test fixture |

---

## Task 1: Package scaffold

**Files:**
- Create: `Examples/CodeReviewer/Package.swift`
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/` (directory placeholder)
- Create: `Examples/CodeReviewer/Tests/CodeReviewerTests/` (directory placeholder)

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p Examples/CodeReviewer/Sources/CodeReviewer/Agents
mkdir -p Examples/CodeReviewer/Sources/CodeReviewer/Tools
mkdir -p Examples/CodeReviewer/Sources/CodeReviewer/Output
mkdir -p Examples/CodeReviewer/Tests/CodeReviewerTests/Fixtures
```

- [ ] **Step 2: Write Package.swift**

```swift
// Examples/CodeReviewer/Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodeReviewer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "CodeReviewer",
            dependencies: [
                .product(name: "Swarm", package: "Swarm")
            ],
            path: "Sources/CodeReviewer",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CodeReviewerTests",
            dependencies: [
                .target(name: "CodeReviewer"),
                .product(name: "Swarm", package: "Swarm")
            ],
            path: "Tests/CodeReviewerTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
```

- [ ] **Step 3: Verify package resolves**

```bash
cd Examples/CodeReviewer && swift package resolve
```

Expected: No errors. Package resolves Swarm from local path.

- [ ] **Step 4: Commit**

```bash
git add Examples/CodeReviewer/Package.swift
git commit -m "feat(example): scaffold CodeReviewer SPM package"
```

---

## Task 2: StreamRenderer

**Files:**
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Output/StreamRenderer.swift`
- Create: `Examples/CodeReviewer/Tests/CodeReviewerTests/StreamRendererTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/CodeReviewerTests/StreamRendererTests.swift
import Testing
@testable import CodeReviewer

@Suite("StreamRenderer")
struct StreamRendererTests {

    @Test("formats security prefix with red color")
    func securityPrefix() {
        let result = StreamRenderer.format("hello", agent: .security)
        #expect(result.contains("[Security]"))
        #expect(result.contains("hello"))
        #expect(result.contains(StreamRenderer.ANSICode.red))
    }

    @Test("formats performance prefix with yellow color")
    func performancePrefix() {
        let result = StreamRenderer.format("world", agent: .performance)
        #expect(result.contains("[Performance]"))
        #expect(result.contains(StreamRenderer.ANSICode.yellow))
    }

    @Test("formats style prefix with blue color")
    func stylePrefix() {
        let result = StreamRenderer.format("test", agent: .style)
        #expect(result.contains("[Style]"))
        #expect(result.contains(StreamRenderer.ANSICode.blue))
    }

    @Test("formats synthesizer prefix with green color")
    func synthesizerPrefix() {
        let result = StreamRenderer.format("summary", agent: .synthesizer)
        #expect(result.contains("[Summary]"))
        #expect(result.contains(StreamRenderer.ANSICode.green))
    }
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd Examples/CodeReviewer && swift test --filter StreamRendererTests
```

Expected: FAIL — `StreamRenderer` not defined.

- [ ] **Step 3: Implement StreamRenderer**

```swift
// Sources/CodeReviewer/Output/StreamRenderer.swift
import Foundation

public enum AgentRole {
    case security, performance, style, synthesizer

    var label: String {
        switch self {
        case .security:    return "[Security]"
        case .performance: return "[Performance]"
        case .style:       return "[Style]"
        case .synthesizer: return "[Summary]"
        }
    }

    var emoji: String {
        switch self {
        case .security:    return "🔴"
        case .performance: return "🟡"
        case .style:       return "🔵"
        case .synthesizer: return "🟢"
        }
    }

    var color: String {
        switch self {
        case .security:    return StreamRenderer.ANSICode.red
        case .performance: return StreamRenderer.ANSICode.yellow
        case .style:       return StreamRenderer.ANSICode.blue
        case .synthesizer: return StreamRenderer.ANSICode.green
        }
    }
}

public enum StreamRenderer {
    public enum ANSICode {
        public static let red    = "\u{001B}[31m"
        public static let yellow = "\u{001B}[33m"
        public static let blue   = "\u{001B}[34m"
        public static let green  = "\u{001B}[32m"
        public static let reset  = "\u{001B}[0m"
        public static let bold   = "\u{001B}[1m"
    }

    /// Formats a token with an agent prefix and ANSI color.
    public static func format(_ text: String, agent: AgentRole) -> String {
        "\(agent.color)\(ANSICode.bold)\(agent.label)\(ANSICode.reset) \(agent.emoji)  \(text)"
    }

    /// Prints a token to stdout unbuffered.
    public static func printToken(_ text: String, agent: AgentRole) {
        let formatted = "\(agent.color)\(text)\(ANSICode.reset)"
        print(formatted, terminator: "")
        fflush(stdout)
    }

    /// Prints a full prefixed line (used for status messages, not streaming tokens).
    public static func printLine(_ text: String, agent: AgentRole) {
        print("\(agent.color)\(ANSICode.bold)\(agent.label)\(ANSICode.reset) \(agent.emoji)  \(text)")
    }

    /// Prints a section header divider.
    public static func printDivider(_ title: String) {
        print("\n\(ANSICode.bold)── \(title) ──\(ANSICode.reset)\n")
    }
}
```

- [ ] **Step 4: Run test — expect PASS**

```bash
cd Examples/CodeReviewer && swift test --filter StreamRendererTests
```

Expected: PASS — all 4 tests green.

- [ ] **Step 5: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/Output/StreamRenderer.swift \
        Examples/CodeReviewer/Tests/CodeReviewerTests/StreamRendererTests.swift
git commit -m "feat(example): add StreamRenderer with ANSI colored agent prefixes"
```

---

## Task 3: ReadFileTool

**Files:**
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Tools/ReadFileTool.swift`
- Create: `Examples/CodeReviewer/Tests/CodeReviewerTests/Fixtures/Sample.swift`
- Create: `Examples/CodeReviewer/Tests/CodeReviewerTests/ReadFileToolTests.swift`

- [ ] **Step 1: Write fixture file**

```swift
// Tests/CodeReviewerTests/Fixtures/Sample.swift
// This file is intentionally imperfect — used as a test fixture.
import Foundation

let apiKey = "sk-abc123-hardcoded"  // hardcoded secret

func fetchUsers(ids: [Int]) -> [String] {
    var results: [String] = []
    for id in ids {
        for _ in 0..<ids.count {  // O(n²)
            results.append("user_\(id)")
        }
    }
    return results
}
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/CodeReviewerTests/ReadFileToolTests.swift
import Testing
import Foundation
@testable import CodeReviewer

@Suite("ReadFileTool")
struct ReadFileToolTests {

    @Test("reads a file and returns its contents")
    func readsFile() throws {
        let fixturePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Sample.swift")
            .path

        let tool = ReadFileTool()
        let contents = try tool.readFile(at: fixturePath)

        #expect(contents.contains("apiKey"))
        #expect(contents.contains("fetchUsers"))
    }

    @Test("throws when file does not exist")
    func throwsOnMissingFile() {
        let tool = ReadFileTool()
        #expect(throws: ReadFileError.self) {
            try tool.readFile(at: "/nonexistent/path/file.swift")
        }
    }
}
```

- [ ] **Step 3: Run test — expect FAIL**

```bash
cd Examples/CodeReviewer && swift test --filter ReadFileToolTests
```

Expected: FAIL — `ReadFileTool` not defined.

- [ ] **Step 4: Implement ReadFileTool**

```swift
// Sources/CodeReviewer/Tools/ReadFileTool.swift
import Foundation
import Swarm

public enum ReadFileError: Error, LocalizedError {
    case fileNotFound(String)
    case readFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .readFailed(let path, let error):
            return "Failed to read \(path): \(error.localizedDescription)"
        }
    }
}

public struct ReadFileTool {
    public init() {}

    /// Reads a file at the given path and returns its string contents.
    public func readFile(at path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ReadFileError.fileNotFound(path)
        }
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw ReadFileError.readFailed(path, error)
        }
    }
}
```

- [ ] **Step 5: Run test — expect PASS**

```bash
cd Examples/CodeReviewer && swift test --filter ReadFileToolTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/Tools/ReadFileTool.swift \
        Examples/CodeReviewer/Tests/CodeReviewerTests/ReadFileToolTests.swift \
        Examples/CodeReviewer/Tests/CodeReviewerTests/Fixtures/Sample.swift
git commit -m "feat(example): add ReadFileTool and test fixture"
```

---

## Task 4: Specialist Agents

**Files:**
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Agents/SecurityAgent.swift`
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Agents/PerformanceAgent.swift`
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Agents/StyleAgent.swift`
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Agents/SynthesizerAgent.swift`
- Create: `Examples/CodeReviewer/Tests/CodeReviewerTests/AgentInitTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/CodeReviewerTests/AgentInitTests.swift
import Testing
import Swarm
@testable import CodeReviewer

// MockInferenceProvider must be defined locally since it's in @testable Swarm
// but Swarm's test utilities aren't exported as a product.
// We define a minimal one here:
actor LocalMock: InferenceProvider {
    func generate(prompt: String, options: InferenceOptions) async throws -> String { "mock" }
    nonisolated func stream(prompt: String, options: InferenceOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func generateWithToolCalls(prompt: String, tools: [ToolSchema], options: InferenceOptions) async throws -> InferenceResponse {
        InferenceResponse(content: "mock", finishReason: .completed)
    }
}

@Suite("Agent Initialization")
struct AgentInitTests {

    @Test("SecurityAgent initializes without throwing")
    func securityAgentInit() async throws {
        let mock = LocalMock()
        let agent = try SecurityAgent.make(provider: mock)
        #expect(agent.configuration.name == "Security")
    }

    @Test("PerformanceAgent initializes without throwing")
    func performanceAgentInit() async throws {
        let mock = LocalMock()
        let agent = try PerformanceAgent.make(provider: mock)
        #expect(agent.configuration.name == "Performance")
    }

    @Test("StyleAgent initializes without throwing")
    func styleAgentInit() async throws {
        let mock = LocalMock()
        let agent = try StyleAgent.make(provider: mock)
        #expect(agent.configuration.name == "Style")
    }

    @Test("SynthesizerAgent initializes without throwing")
    func synthesizerAgentInit() async throws {
        let mock = LocalMock()
        let agent = try SynthesizerAgent.make(provider: mock)
        #expect(agent.configuration.name == "Synthesizer")
    }
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd Examples/CodeReviewer && swift test --filter AgentInitTests
```

Expected: FAIL — agent factory functions not defined.

- [ ] **Step 3: Implement SecurityAgent**

```swift
// Sources/CodeReviewer/Agents/SecurityAgent.swift
import Swarm

public enum SecurityAgent {
    public static func make(provider: any InferenceProvider) throws -> Agent {
        var config = AgentConfiguration.default
        config.name = "Security"
        config.maxIterations = 1
        config.modelSettings = .precise  // temperature 0.2, no stop sequences

        return try Agent(
            provider,
            instructions: """
            You are a Swift security expert performing a code review.
            Analyze the provided Swift code and identify security issues including:
            - Hardcoded secrets, API keys, tokens, or passwords
            - Force unwraps (`!`) that could cause crashes in production
            - SQL injection, command injection, or path traversal vectors
            - Insecure data storage (UserDefaults for sensitive data, unencrypted files)
            - Unsafe use of `eval`-equivalent patterns or `NSPredicate` with user input

            For each issue, prefix with severity: [CRITICAL], [HIGH], [MEDIUM], or [LOW].
            Be concise. One finding per line. If no issues found, say "No security issues found."
            """,
            configuration: config,
            memory: ConversationMemory(maxMessages: 10)
        )
    }
}
```

- [ ] **Step 4: Implement PerformanceAgent**

```swift
// Sources/CodeReviewer/Agents/PerformanceAgent.swift
import Swarm

public enum PerformanceAgent {
    public static func make(provider: any InferenceProvider) throws -> Agent {
        var config = AgentConfiguration.default
        config.name = "Performance"
        config.maxIterations = 1
        config.modelSettings = .precise

        return try Agent(
            provider,
            instructions: """
            You are a Swift performance expert performing a code review.
            Analyze the provided Swift code and identify performance issues including:
            - O(n²) or worse algorithmic complexity in loops
            - Unnecessary allocations (creating objects inside tight loops)
            - Retain cycles (strong reference cycles in closures or delegates)
            - Blocking the main thread (synchronous network/disk I/O on main)
            - Inefficient collection operations (repeated `contains`, `filter` on large sets)

            For each issue, prefix with severity: [CRITICAL], [HIGH], [MEDIUM], or [LOW].
            Be concise. One finding per line. If no issues found, say "No performance issues found."
            """,
            configuration: config,
            memory: ConversationMemory(maxMessages: 10)
        )
    }
}
```

- [ ] **Step 5: Implement StyleAgent**

```swift
// Sources/CodeReviewer/Agents/StyleAgent.swift
import Swarm

public enum StyleAgent {
    public static func make(provider: any InferenceProvider) throws -> Agent {
        var config = AgentConfiguration.default
        config.name = "Style"
        config.maxIterations = 1
        config.modelSettings = .precise

        return try Agent(
            provider,
            instructions: """
            You are a Swift style and architecture expert performing a code review.
            Analyze the provided Swift code and identify style and design issues including:
            - Non-idiomatic Swift (use guard, prefer value types, use `let` over `var`)
            - SOLID principle violations (god objects, tight coupling, missing protocols)
            - Poor naming (unclear abbreviations, misleading names, Hungarian notation)
            - Dead code (unused variables, unreachable branches, commented-out code)
            - Missing error handling (silent failures, empty catch blocks)

            For each issue, prefix with severity: [HIGH], [MEDIUM], or [LOW].
            Be concise. One finding per line. If no issues found, say "No style issues found."
            """,
            configuration: config,
            memory: ConversationMemory(maxMessages: 10)
        )
    }
}
```

- [ ] **Step 6: Implement SynthesizerAgent**

```swift
// Sources/CodeReviewer/Agents/SynthesizerAgent.swift
import Swarm

public enum SynthesizerAgent {
    public static func make(provider: any InferenceProvider) throws -> Agent {
        var config = AgentConfiguration.default
        config.name = "Synthesizer"
        config.maxIterations = 1
        config.timeout = .seconds(120)  // larger input prompt needs more time
        config.modelSettings = .precise
        // No memory: synthesizer is stateless — it receives all three reports
        // in a single shot and produces one output. Multi-turn context is not needed.

        return try Agent(
            provider,
            instructions: """
            You receive three code review reports from specialist agents (Security, Performance, Style).
            Synthesize them into a single prioritized action list.

            Format your output as:

            ## Must Fix 🚨
            (CRITICAL/HIGH issues that block shipping)

            ## Should Fix ⚠️
            (MEDIUM issues that matter but aren't blockers)

            ## Consider 💡
            (LOW/style issues worth noting)

            Be ruthless about priority. Avoid duplication across sections.
            If a category has no items, omit it entirely.
            """,
            configuration: config,
            inputGuardrails: [InputGuard.notEmpty()]
        )
    }
}
```

- [ ] **Step 7: Run tests — expect PASS**

```bash
cd Examples/CodeReviewer && swift test --filter AgentInitTests
```

Expected: PASS — all 4 agents initialize without throwing.

- [ ] **Step 8: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/Agents/
git commit -m "feat(example): add four agent factory functions (Security, Performance, Style, Synthesizer)"
```

---

## Task 5: Runner

**Files:**
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/Runner.swift`
- Modify: `Examples/CodeReviewer/Tests/CodeReviewerTests/RunnerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/CodeReviewerTests/RunnerTests.swift
import Testing
import Foundation
@testable import CodeReviewer

@Suite("Runner")
struct RunnerTests {

    @Test("throws when API key is missing")
    func throwsOnMissingKey() async {
        await #expect(throws: RunnerError.self) {
            try await Runner.run(filePath: "/any/file.swift", apiKey: "", model: "any")
        }
    }

    @Test("throws when file does not exist")
    func throwsOnMissingFile() async {
        await #expect(throws: RunnerError.self) {
            try await Runner.run(
                filePath: "/nonexistent/path/file.swift",
                apiKey: "sk-fake",
                model: "anthropic/claude-3.5-sonnet"
            )
        }
    }
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd Examples/CodeReviewer && swift test --filter RunnerTests
```

Expected: FAIL — `Runner` not defined.

- [ ] **Step 3: Implement Runner**

```swift
// Sources/CodeReviewer/Runner.swift
import Foundation
import Swarm

public enum RunnerError: Error, LocalizedError {
    case missingAPIKey
    case fileNotFound(String)
    case allAnalysesFailed

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "❌  OPENROUTER_API_KEY not set. Get a key at https://openrouter.ai"
        case .fileNotFound(let path):
            return "❌  File not found: \(path)"
        case .allAnalysesFailed:
            return "❌  All specialist analyses returned empty. Cannot synthesize."
        }
    }
}

public enum Runner {

    public static func run(filePath: String, apiKey: String, model: String) async throws {
        // Validate inputs
        guard !apiKey.isEmpty else { throw RunnerError.missingAPIKey }
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw RunnerError.fileNotFound(filePath)
        }

        // Read source file
        let fileTool = ReadFileTool()
        let code = try fileTool.readFile(at: filePath)

        // Build provider
        let provider = LLM.openRouter(key: apiKey, model: model)

        // Build agents
        let securityAgent    = try SecurityAgent.make(provider: provider)
        let performanceAgent = try PerformanceAgent.make(provider: provider)
        let styleAgent       = try StyleAgent.make(provider: provider)
        let synthesizer      = try SynthesizerAgent.make(provider: provider)

        StreamRenderer.printDivider("Swarm Code Review — \(URL(fileURLWithPath: filePath).lastPathComponent)")

        // Fan-out: run three agents in parallel
        async let securityOutput    = stream(agent: securityAgent,    code: code, role: .security)
        async let performanceOutput = stream(agent: performanceAgent, code: code, role: .performance)
        async let styleOutput       = stream(agent: styleAgent,       code: code, role: .style)

        let (sec, perf, style) = try await (securityOutput, performanceOutput, styleOutput)

        // Guard against all-empty outputs
        let combined = [sec, perf, style].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !combined.isEmpty else { throw RunnerError.allAnalysesFailed }

        // Synthesis
        StreamRenderer.printDivider("Synthesis")
        _ = try await stream(agent: synthesizer, code: combined, role: .synthesizer)

        print("")  // final newline
    }

    // MARK: - Private

    /// Streams an agent's output, printing tokens with a colored prefix.
    /// Returns the full accumulated output text.
    @discardableResult
    private static func stream(
        agent: Agent,
        code: String,
        role: AgentRole
    ) async throws -> String {
        var accumulated = ""
        do {
            // Print the agent label before streaming begins
            print("\(role.color)\(StreamRenderer.ANSICode.bold)\(role.label)\(StreamRenderer.ANSICode.reset) \(role.emoji)  ", terminator: "")
            fflush(stdout)

            for try await event in agent.stream(code) {
                if case .output(.token(let text)) = event {
                    accumulated += text
                    StreamRenderer.printToken(text, agent: role)
                }
            }
            print("")  // newline after agent finishes
        } catch {
            print("\n\(role.label) ⚠️  Analysis failed: \(error.localizedDescription). Skipping.")
        }
        return accumulated
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd Examples/CodeReviewer && swift test --filter RunnerTests
```

Expected: PASS — both error path tests pass.

- [ ] **Step 5: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/Runner.swift \
        Examples/CodeReviewer/Tests/CodeReviewerTests/RunnerTests.swift
git commit -m "feat(example): add Runner with parallel fan-out and synthesis"
```

---

## Task 6: Guardrail error path test

**Files:**
- Modify: `Examples/CodeReviewer/Sources/CodeReviewer/Runner.swift` (extract `combineAndGuard` helper)
- Modify: `Examples/CodeReviewer/Tests/CodeReviewerTests/RunnerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `RunnerTests.swift`:

```swift
@Test("allAnalysesFailed error has correct message")
func allAnalysesFailedMessage() {
    let error = RunnerError.allAnalysesFailed
    #expect(error.errorDescription == "❌  All specialist analyses returned empty. Cannot synthesize.")
}

@Test("combineOutputs throws allAnalysesFailed when all outputs are empty")
func combineOutputsThrowsOnAllEmpty() throws {
    #expect(throws: RunnerError.allAnalysesFailed as RunnerError) {
        try Runner.combineOutputs(security: "", performance: "", style: "")
    }
}

@Test("combineOutputs succeeds when at least one output is non-empty")
func combineOutputsSucceedsPartially() throws {
    let result = try Runner.combineOutputs(
        security: "Found issue",
        performance: "",
        style: ""
    )
    #expect(result.contains("Found issue"))
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd Examples/CodeReviewer && swift test --filter "combineOutputs"
```

Expected: FAIL — `Runner.combineOutputs` not defined.

- [ ] **Step 3: Extract `combineOutputs` static helper on Runner**

Add to `Runner.swift` (above the `stream` private method):

```swift
/// Combines specialist outputs, filtering empty strings.
/// Throws `allAnalysesFailed` if all three are empty.
public static func combineOutputs(security: String, performance: String, style: String) throws -> String {
    let combined = [
        security.isEmpty   ? nil : "## Security\n\(security)",
        performance.isEmpty ? nil : "## Performance\n\(performance)",
        style.isEmpty      ? nil : "## Style\n\(style)"
    ].compactMap { $0 }.joined(separator: "\n\n")

    guard !combined.isEmpty else { throw RunnerError.allAnalysesFailed }
    return combined
}
```

Update `Runner.run()` to use it (replace the inline `filter/joined/guard` block):

```swift
let combined = try Runner.combineOutputs(security: sec, performance: perf, style: style)
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd Examples/CodeReviewer && swift test --filter "combineOutputs"
```

Expected: PASS — all 3 new tests green.

- [ ] **Step 5: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/Runner.swift \
        Examples/CodeReviewer/Tests/CodeReviewerTests/RunnerTests.swift
git commit -m "test(example): add TDD tests for combineOutputs guardrail logic"
```

---

## Task 7: main.swift (CLI entry point)

**Files:**
- Create: `Examples/CodeReviewer/Sources/CodeReviewer/main.swift`

- [ ] **Step 1: Implement main.swift**

```swift
// Sources/CodeReviewer/main.swift
import Foundation

// Parse arguments
var args = CommandLine.arguments.dropFirst()  // drop executable name

var filePath: String?
var apiKey: String = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
var model: String = ProcessInfo.processInfo.environment["OPENROUTER_MODEL"] ?? "anthropic/claude-3.5-sonnet"

// Simple arg parsing
var argIterator = args.makeIterator()
while let arg = argIterator.next() {
    switch arg {
    case "--key":
        apiKey = argIterator.next() ?? apiKey
    case "--model":
        model = argIterator.next() ?? model
    case _ where !arg.hasPrefix("-"):
        filePath = arg
    default:
        break
    }
}

guard let path = filePath else {
    print("❌  Usage: swift run CodeReviewer <file.swift> [--model <model>] [--key <api-key>]")
    exit(1)
}

// Run
do {
    try await Runner.run(filePath: path, apiKey: apiKey, model: model)
} catch let error as RunnerError {
    print(error.errorDescription ?? error.localizedDescription)
    exit(1)
} catch {
    print("❌  Unexpected error: \(error.localizedDescription)")
    exit(1)
}
```

- [ ] **Step 2: Verify it builds**

```bash
cd Examples/CodeReviewer && swift build
```

Expected: Build succeeded.

- [ ] **Step 3: Smoke test with fixture file**

```bash
cd Examples/CodeReviewer
OPENROUTER_API_KEY=<your-key> swift run CodeReviewer Tests/CodeReviewerTests/Fixtures/Sample.swift
```

Expected: Three colored streams fire in parallel, then a synthesis section.

- [ ] **Step 4: Commit**

```bash
git add Examples/CodeReviewer/Sources/CodeReviewer/main.swift
git commit -m "feat(example): add CLI entry point with arg parsing"
```

---

## Task 8: README

**Files:**
- Create: `Examples/CodeReviewer/README.md`

- [ ] **Step 1: Write README**

```markdown
# CodeReviewer — Swarm Example

A CLI tool that fans out three specialist AI agents in parallel to review a Swift file, streaming their findings live to the terminal.

## What it demonstrates

| Swarm Feature | Where |
|---|---|
| `try Agent(...)` inline construction | `Agents/*.swift` |
| `.stream()` + `.output(.token(...))` | `Runner.swift` |
| Parallel `TaskGroup` fan-out | `Runner.swift` |
| `ConversationMemory` | Each specialist agent |
| `InputGuard.notEmpty()` | `SynthesizerAgent.swift` |
| `LLM.openRouter(key:model:)` | `Runner.swift` |
| `AgentConfiguration` (name, timeout) | All agents |
| `InferenceOptions.precise` | All specialist agents |

## Usage

```bash
# Set your OpenRouter API key
export OPENROUTER_API_KEY=sk-...

# Review a Swift file
swift run CodeReviewer path/to/YourFile.swift

# Use a different model
swift run CodeReviewer path/to/YourFile.swift --model minimax/minimax-01
```

## Output

```
── Swarm Code Review — YourFile.swift ──

[Security] 🔴  [HIGH] Hardcoded API key on line 3...
[Performance] 🟡  [MEDIUM] O(n²) loop in fetchUsers()...
[Style] 🔵  [LOW] Prefer guard-let over nested if-let...

── Synthesis ──

[Summary] 🟢  ## Must Fix 🚨
- Remove hardcoded API key (Security: HIGH)
...
```

## Get an OpenRouter key

Sign up at [openrouter.ai](https://openrouter.ai) — free tier available.
```

- [ ] **Step 2: Commit**

```bash
git add Examples/CodeReviewer/README.md
git commit -m "docs(example): add CodeReviewer README with usage and feature table"
```

---

## Task 9: Run full test suite

- [ ] **Step 1: Run all tests**

```bash
cd Examples/CodeReviewer && swift test
```

Expected: All tests pass. No compilation errors or warnings.

- [ ] **Step 2: Verify build is clean**

```bash
cd Examples/CodeReviewer && swift build 2>&1 | grep -E "error:|warning:"
```

Expected: No errors. Warnings about strict concurrency are acceptable if they're in Swarm internals (not in CodeReviewer source).

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore(example): verify full test suite passes"
```

---

## Summary

| Task | Deliverable |
|---|---|
| 1 | SPM package scaffold |
| 2 | `StreamRenderer` — ANSI colored output |
| 3 | `ReadFileTool` — file I/O with error types |
| 4 | 4 agent factory functions |
| 5 | `Runner` — parallel fan-out orchestration |
| 6 | Guardrail error path test |
| 7 | `main.swift` — CLI entry point |
| 8 | `README.md` |
| 9 | Full test suite verification |
