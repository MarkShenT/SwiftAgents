# Guardrail Integration Tests - Quick Reference Card

## 🎯 Test File
`GuardrailIntegrationTests.swift` - 615 lines, 14 integration tests

## 📊 Test Breakdown

### 1. Agent + Input Guardrails (3 tests)
```
✓ testAgentWithInputGuardrailPassed          - Happy path
✓ testAgentWithInputGuardrailTriggered       - Tripwire path  
✓ testAgentWithMultipleInputGuardrails       - Sequential execution
```

### 2. Agent + Output Guardrails (2 tests)
```
✓ testAgentWithOutputGuardrailPassed         - Output validation passes
✓ testAgentWithOutputGuardrailTriggered      - Output validation fails
```

### 3. Tool + Guardrails (3 tests)
```
✓ testToolExecutionWithInputGuardrail        - Tool arg validation
✓ testToolExecutionWithOutputGuardrail       - Tool result validation
⏳ testToolRegistryWithGuardrails             - Full integration (pending)
```

### 4. Combined Scenarios (3 tests)
```
✓ testAgentWithBothInputAndOutputGuardrails  - E2E flow
✓ testGuardrailWithAgentContext              - Context passing
✓ testGuardrailErrorPropagation              - Error handling
```

### 5. Edge Cases (3 tests)
```
✓ testEmptyGuardrailArrays                   - No guardrails
✓ testGuardrailMetadataPreserved             - Metadata handling
✓ testParallelInputGuardrails                - Concurrent execution
```

## 🔑 Key Patterns

### Test Structure
```swift
@Test("Description with context")
func testSomething() async throws {
    // Given: Setup
    let agent = await MockGuardrailAgent(...)
    let guardrail = InputGuard(...)
    
    // When: Execute
    let results = try await runner.runInputGuardrails(...)
    
    // Then: Assert
    #expect(results[0].result.tripwireTriggered == false)
}
```

### Mock Agent
```swift
let agent = await MockGuardrailAgent(
    name: "TestAgent",
    responseHandler: { input in
        "Custom response"
    }
)
```

### Guardrail Creation
```swift
let inputGuardrail = InputGuard(name: "validator") { input, agent, ctx in
    if someCondition {
        return .tripwire(message: "Failed", outputInfo: .string("details"))
    }
    return .passed(message: "Success")
}
```

## 🧪 Real-World Scenarios Tested

| Scenario | Test | Line |
|----------|------|------|
| PII Detection | testAgentWithInputGuardrailTriggered | 98 |
| Profanity Filter | testAgentWithOutputGuardrailTriggered | 207 |
| Code Injection | testToolExecutionWithInputGuardrail | 249 |
| RBAC | testGuardrailWithAgentContext | 423 |
| Empty Results | testToolExecutionWithOutputGuardrail | 293 |

## 🔄 Running Tests

```bash
# All integration tests
swift test --filter GuardrailIntegrationTests

# Specific test
swift test --filter testAgentWithInputGuardrailPassed

# Verbose
swift test --filter GuardrailIntegrationTests --verbose
```

## 📦 Dependencies

### ✅ Already Implemented
- GuardrailError
- AgentContext  
- AgentResult
- MockInferenceProvider
- MockTool

### ⏳ Needs Implementation
- GuardrailRunner
- InputGuardrail protocol
- OutputGuardrail protocol
- ToolInputGuardrail protocol
- ToolOutputGuardrail protocol
- Closure*Guardrail implementations
- ToolGuardrailData structs

## 🎨 Test Assertions

```swift
// Guardrail passed
#expect(result.tripwireTriggered == false)
#expect(result.message == "Expected message")

// Guardrail triggered
await #expect(throws: GuardrailError.self) {
    try await runner.runInputGuardrails(...)
}

// Error details
if case .inputTripwireTriggered(let name, let msg, _) = error {
    #expect(name == "guardrail_name")
}

// Metadata
#expect(result.metadata["key"]?.stringValue == "value")

// Context
let role = await context.get("user_role")?.stringValue
#expect(role == "admin")
```

## 🚀 Next Steps

1. Implement GuardrailRunner actor
2. Implement guardrail protocols
3. Add Agent.inputGuardrails property
4. Add Tool.inputGuardrails property  
5. Wire up agent.run() method
6. Update ToolRegistry.execute()
7. Run tests: `swift test --filter GuardrailIntegrationTests`

## 📝 Notes

- Tests use Swift Testing framework (not XCTest)
- All async with proper actor isolation
- Mock agent fully implements Agent protocol
- Parallel execution explicitly tested
- Context flows through all layers
