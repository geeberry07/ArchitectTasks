# ArchitectTasks

A two-agent, task-driven architecture for intelligent code analysis and transformation.

**Tasks are the unit of intelligence** — not files, not diffs, not prompts.

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Agent A    │────▶│   Human     │────▶│  Agent B    │
│  (Planner)  │     │  (Governor) │     │  (Builder)  │
└─────────────┘     └─────────────┘     └─────────────┘
      │                    │                    │
      ▼                    ▼                    ▼
   Findings ──▶ Tasks ──▶ Approval ──▶ Execution ──▶ Diff
```

## Quick Start

```bash
# Build
swift build

# Analyze a project
swift run architect-cli analyze /path/to/project

# Run with policy-based approval
swift run architect-cli run . --policy moderate

# CI mode (fails if issues found)
swift run architect-cli run . --ci

# Self-analyze
swift run architect-cli self
```

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/yourorg/ArchitectTasks", from: "0.1.0")
]
```

## Architecture

```
ArchitectTasks/
├── ArchitectCore       # Models, Protocols, Persistence
├── ArchitectAnalysis   # SwiftSyntax analyzers (SwiftUI bindings, complexity)
├── ArchitectPlanner    # Agent A (task generation from findings)
├── ArchitectExecutor   # Agent B (deterministic SwiftSyntax transforms)
├── ArchitectHost       # Host contract + LocalHost implementation
├── architect-cli       # CLI executable
└── ArchitectMenuBar    # macOS menu bar app (optional)
```

## Key Features

### 1. Policy-Based Approval

Define rules for automatic task approval/rejection:

```swift
let policy = ApprovalPolicy(
    name: "Team Policy",
    rules: [
        PolicyRule(
            condition: .intentCategory(.documentation),
            decision: .allow,
            reason: "Documentation is safe"
        ),
        PolicyRule(
            condition: .intentCategory(.architecture),
            decision: .deny,
            reason: "Architecture changes need review"
        ),
        PolicyRule(
            condition: .all([
                .scopeType(.file),
                .confidenceAbove(0.8),
                .maxSteps(3)
            ]),
            decision: .allow,
            reason: "High-confidence, small scope"
        )
    ],
    defaultDecision: .requireHuman
)
```

Built-in policies:
- `conservative` - Only auto-approve documentation
- `moderate` - Auto-approve high-confidence, single-file changes
- `permissive` - Auto-approve most, deny architecture
- `ci` - Report only, never auto-approve
- `strict` - Require human approval for everything

### 2. Task Persistence

Full history of task runs for replay and audit:

```swift
// Save runs to disk
let store = try FileRunStore.default()

let host = LocalHost(
    projectRoot: url,
    policy: .moderate,
    store: store,
    approvalHandler: { ... }
)

// Query history
let recent = try await store.loadRecent(limit: 10)
let failed = try await store.loadRuns(withOutcome: .failed)
```

### 3. Deterministic Transforms

Pure syntax rewriting using SwiftSyntax AST manipulation, no LLMs:

```swift
let executor = DeterministicExecutor()

let result = try executor.executeTransform(
    intent: .addStateObject(property: "viewModel", type: "ViewModel", in: "View.swift"),
    source: sourceCode,
    context: TransformContext(filePath: "View.swift")
)

// result.transformedSource contains the modified code
// result.diff contains the unified diff
```

Available transforms:
- `SyntaxStateObjectTransform` - Adds @StateObject/@ObservedObject wrappers
- `SyntaxBindingTransform` - Adds @Binding wrappers
- `SyntaxImportTransform` - Adds import statements

### 4. Complexity Analysis

Detects code quality issues with configurable thresholds:

```swift
let analyzer = ComplexityAnalyzer(thresholds: .strict)
let findings = try analyzer.analyze(fileAt: path, content: source)

// Detects:
// - Long functions (> 50 lines)
// - Too many parameters (> 5)
// - Deep nesting (> 4 levels)
// - Large files (> 500 lines)
// - High cyclomatic complexity (> 10)
```

Findings automatically generate refactoring tasks:
- `extractFunction` - Break up long/complex functions
- `reduceNesting` - Apply guard/early return patterns
- `reduceParameters` - Create parameter objects
- `splitFile` - Separate concerns into multiple files

### 5. CI Integration

```yaml
# GitHub Actions
- name: Check code quality
  run: |
    swift run architect-cli run . --ci
    # Exits 0 if clean, 1 if issues found
```

```bash
# Local CI check
swift run architect-cli run . --ci --policy strict
```

## CLI Reference

```
Usage: architect-cli <command> [options]

Commands:
  analyze <path>      Analyze and show findings/tasks
  run <path>          Full pipeline with approval
  self                Analyze this package
  help                Show help
  version             Show version

Options:
  --auto-approve      Auto-approve low-risk tasks
  --policy <name>     Use policy: conservative, moderate, permissive, ci, strict
  --ci                Exit with error if tasks proposed
  --dry-run           Don't apply changes (default)
```

## Programmatic Usage

```swift
import ArchitectHost

// Create host with policy
let host = LocalHost(
    projectRoot: URL(fileURLWithPath: "."),
    config: .default,
    policy: .moderate,
    store: try FileRunStore.default(),
    approvalHandler: { task in
        // Custom approval logic
        var approved = task
        approved.approve()
        return TaskApprovalResult(task: approved, decision: .approved)
    }
)

// Run pipeline
let result = try await host.run()
print(result.summary)
```

## Custom Policies

```swift
// Allow test file changes, deny project-wide
let policy = ApprovalPolicy(
    name: "Test-Friendly",
    rules: [
        PolicyRule(
            condition: .filePattern("*Tests.swift"),
            decision: .allow
        ),
        PolicyRule(
            condition: .scopeType(.project),
            decision: .deny
        )
    ],
    defaultDecision: .requireHuman
)

// Combine conditions
let complexCondition = PolicyCondition.all([
    .intentCategory(.dataFlow),
    .confidenceAbove(0.7),
    .not(.scopeType(.project))
])
```

## Extending

### Custom Analyzers

```swift
struct ComplexityAnalyzer: Analyzer {
    var supportedFindingTypes: [Finding.FindingType] { [.highComplexity] }
    
    func analyze(fileAt path: String, content: String) throws -> [Finding] {
        // Your analysis
    }
}
```

### Custom Transforms

```swift
struct MyTransform: DeterministicTransform {
    var supportedIntents: [String] { ["myIntent"] }
    
    func apply(to source: String, intent: TaskIntent, context: TransformContext) throws -> TransformResult {
        // Pure syntax transformation
    }
}

TransformRegistry.shared.register(MyTransform())
```

### Custom Hosts

```swift
final class SlackNotifyHost: ArchitectHost {
    func didComplete(task: AgentTask, result: TaskRunResult) async {
        // Post to Slack
    }
}
```

## What Makes This Industrial

| Property | Implementation |
|----------|----------------|
| Queueable | Tasks are Codable data |
| Retryable | Steps are atomic |
| Auditable | Full run history persisted |
| Policy-driven | Declarative approval rules |
| Deterministic | Pure syntax transforms |
| CI-ready | Exit codes for automation |

## Test Coverage

77 tests covering:
- Task lifecycle
- Policy evaluation
- Sandbox validation
- Deterministic transforms (regex + SwiftSyntax AST)
- Complexity analysis
- Task generation rules
- Host integration

```bash
swift test
```

## License

MIT
