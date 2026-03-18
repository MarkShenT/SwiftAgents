# AI Code Reviewer — Design Spec
**Date:** 2026-03-18
**Branch:** `examples/ai-code-reviewer`
**Status:** Approved

---

## Overview

A standalone Swift CLI example app demonstrating Swarm's multi-agent capabilities. Three specialist agents analyze a Swift source file in parallel using Swarm's streaming API, with live colored terminal output. A fourth agent synthesizes their findings into a prioritized action list.

**Primary audience:** Framework evaluators deciding whether to adopt Swarm.
**Success criteria:** A developer can clone the repo, set one env var, and see three agents streaming interleaved analysis in under 60 seconds.

---

## Location

```
Examples/
└── CodeReviewer/
    ├── Package.swift
    ├── README.md
    └── Sources/
        └── CodeReviewer/
            ├── main.swift
            ├── Agents/
            │   ├── SecurityAgent.swift
            │   ├── PerformanceAgent.swift
            │   ├── StyleAgent.swift
            │   └── SynthesizerAgent.swift
            ├── Tools/
            │   └── ReadFileTool.swift
            ├── Output/
            │   └── StreamRenderer.swift
            └── Runner.swift
```

A standalone SPM package with its own `Package.swift` that depends on Swarm via local path (`../../`). This presents the "consumer perspective" — showing exactly how a developer would adopt Swarm in their own project.

---

## Architecture

### Orchestration Pattern: Parallel Fan-Out

```
Runner
 ├── 1. Read source file → String
 ├── 2. Fan-out (simultaneous)
 │   ├── Task { securityAgent.stream(code) }
 │   ├── Task { performanceAgent.stream(code) }
 │   └── Task { styleAgent.stream(code) }
 ├── 3. Await all three → collect outputs
 └── 4. synthesizerAgent.stream(combined) → final report
```

Three agents run as independent Swift `Task`s. Each consumes an `AsyncThrowingStream<AgentEvent, Error>` from `.stream()`, printing tokens with a colored ANSI prefix as they arrive. Tasks are collected via `TaskGroup`, awaiting all three before synthesis.

---

## Components

### Agent Definitions

All agents use the V3 canonical inline construction pattern.

**SecurityAgent** (`color: red 🔴`)
Identifies: hardcoded secrets, force unwraps, injection vectors, insecure storage.
Leads each finding with a severity tag: `[CRITICAL]`, `[HIGH]`, `[MEDIUM]`, `[LOW]`.

**PerformanceAgent** (`color: yellow 🟡`)
Identifies: O(n²) loops, unnecessary allocations, retain cycles, synchronous blocking on main thread.

**StyleAgent** (`color: blue 🔵`)
Identifies: naming violations, SOLID principle breaches, non-idiomatic Swift, dead code.

**SynthesizerAgent** (`color: green 🟢`)
Receives all three reports as a single prompt. Outputs a final prioritized action list:
- **Must fix** — correctness/security blockers
- **Should fix** — quality issues
- **Consider** — style and polish

All four agents share the same `InferenceProvider` (OpenRouter). Each specialist has its own `ConversationMemory(maxMessages: 10)`.

### Provider

```swift
.openRouter(key: apiKey, model: model)
```

Default model: `anthropic/claude-3.5-sonnet`. Configurable via `--model` flag or `OPENROUTER_MODEL` env var.

### ReadFileTool

A lightweight `AnyJSONTool` conformance that reads a file path from disk and returns its contents as a `String`. Used internally by `Runner` before fan-out (not passed to agents — file contents are injected directly into the prompt).

### StreamRenderer

Thin ANSI escape code wrapper. Formats output as:
```
[Security] 🔴  Found hardcoded API key on line 23...
[Performance] 🟡  O(n²) loop detected in fetchUsers()...
[Style] 🔵  Prefer guard-let over nested if-let...
[Summary] 🟢  ## Must Fix ...
```

Prints are unbuffered (`fflush(stdout)` after each token) for real-time streaming feel.

### Guardrails

`NotEmptyGuardrail` on the synthesizer's input — catches empty analysis results before wasting an API call on synthesis. No output guardrails.

---

## CLI Interface

```bash
# Recommended: env var
OPENROUTER_API_KEY=sk-... swift run CodeReviewer Sources/MyApp/ContentView.swift

# With explicit flags
swift run CodeReviewer <file> [--model <model-id>] [--key <api-key>]
```

### Error Messages (fail fast)

| Condition | Message |
|---|---|
| No file argument | `❌  Usage: swift run CodeReviewer <file.swift>` |
| File not found | `❌  File not found: <path>` |
| No API key | `❌  OPENROUTER_API_KEY not set. Get a key at openrouter.ai` |
| Agent failure | `[Security] ⚠️  Analysis failed: <reason>. Skipping.` (non-fatal) |

Individual agent failures are caught and reported inline — one failure does not abort the others.

---

## Swarm Features Showcased

| Feature | Where Used |
|---|---|
| `Agent` inline construction | All four agent files |
| `.stream()` + `AgentEvent` | `Runner.swift` streaming loop |
| Parallel `TaskGroup` | `Runner.swift` fan-out |
| `ConversationMemory` | Each specialist agent |
| `NotEmptyGuardrail` | `SynthesizerAgent` |
| `.openRouter(key:model:)` | Provider factory |
| `AgentConfiguration` (name) | All agents |
| `InferenceOptions` (.codeGeneration preset) | Specialist agents |

---

## Testing

**Framework:** Swift Testing (`@Test`, `#expect`)
**Network:** None — uses `MockInferenceProvider` from Swarm's test utilities.

| Test | What it verifies |
|---|---|
| `ReadFileTool` reads fixture | File I/O correctness |
| `StreamRenderer` formatting | ANSI prefix output |
| All four agents initialize | No-throw construction |
| Runner fails on missing key | Fast-fail error path |
| Runner fails on missing file | Fast-fail error path |

LLM output and live streaming are explicitly out of scope for unit tests.

---

## Out of Scope

- GitHub PR / git diff input (future example)
- MiniMax native provider (use OpenRouter passthrough)
- Interactive TUI / web UI
- Saving reports to disk
- CI integration
