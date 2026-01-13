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
├── ArchitectAnalysis   # SwiftSyntax analyzers (SwiftUI, complexity, naming, dead code)
├── ArchitectPlanner    # Agent A (task generation from findings)
├── ArchitectExecutor   # Agent B (deterministic SwiftSyntax transforms)
├── ArchitectHost       # Host contract + LocalHost implementation
├── architect-cli       # CLI executable (with watch mode, JSON export)
├── ArchitectMenuBar    # macOS menu bar app
└── ArchitectLSP        # Language Server Protocol implementation
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
  ci <path>           CI mode: exit 1 if issues found
  watch <path>        Watch mode: re-analyze on file changes
  export-policy       Export policy to JSON
  self                Analyze this package
  help                Show help
  version             Show version

Global Options:
  --json              Output results as JSON

Run Options:
  --auto-approve      Auto-approve based on policy
  --policy <name>     Use policy: conservative, moderate, permissive, ci, strict
  --apply             Apply changes (default: dry run)

Watch Options:
  --debounce <sec>    Wait time before re-analyzing (default: 1.0)
```

### Watch Mode

Re-analyze automatically when files change:

```bash
# Watch current directory
swift run architect-cli watch .

# Watch with custom debounce
swift run architect-cli watch . --debounce 2.0
```

### Interactive Mode

Review and apply transforms one-by-one with undo capability:

```bash
# Start interactive mode
swift run architect-cli interactive .
swift run architect-cli i .
```

Interactive mode provides:
- Step-by-step task review
- Preview changes before applying
- Colored diff output
- Undo last transform
- Write changes to disk when ready
- Re-analyze after changes

Commands in interactive mode:
| Key | Action |
|-----|--------|
| `a` | Apply current transform |
| `s` | Skip to next task |
| `p` | Preview changes |
| `d` | Show diff of all changes |
| `u` | Undo last transform |
| `l` | List all tasks |
| `g` | Go to specific task |
| `w` | Write changes to disk |
| `r` | Refresh analysis |
| `q` | Quit |

### JSON Export

Get machine-readable output for integration:

```bash
# JSON analysis report
swift run architect-cli analyze . --json > report.json

# CI with JSON output
swift run architect-cli ci . --json
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

## Language Server Protocol

Use ArchitectTasks with any LSP-compatible editor:

```bash
# Build the language server
swift build --product architect-lsp

# Configure your editor to use:
.build/debug/architect-lsp /path/to/project
```

Capabilities:
- `textDocument/publishDiagnostics` - Shows findings as diagnostics
- `textDocument/codeAction` - Suggests fixes based on tasks
- `workspace/executeCommand` - Executes approved transforms

## Analyzers

Built-in analyzers:

| Analyzer | Detects |
|----------|---------|
| `SwiftUIBindingAnalyzer` | Missing @StateObject, @ObservedObject, @Binding |
| `ComplexityAnalyzer` | Long functions, deep nesting, high cyclomatic complexity |
| `DeadCodeAnalyzer` | Unreachable code, unused private members |
| `NamingAnalyzer` | Naming convention violations |
| `SecurityAnalyzer` | Force unwraps, force try, hardcoded secrets, unsafe APIs |

## Transform Pipeline

Composable transforms with dependency ordering and conflict detection:

```swift
import ArchitectExecutor

let pipeline = TransformPipeline.standard()

// Execute multiple transforms in order
let result = try pipeline.execute(
    intents: [
        .addStateObject(property: "vm", type: "ViewModel", in: "View.swift"),
        .addBinding(property: "isActive", in: "View.swift"),
    ],
    source: source,
    context: TransformContext(filePath: "View.swift")
)

// Undo last transform
let undone = pipeline.undoLast()

// Get transform history
let history = pipeline.history
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

109 tests covering:
- Task lifecycle
- Policy evaluation
- Sandbox validation
- Deterministic transforms (regex + SwiftSyntax AST)
- Complexity analysis
- Security analysis
- Task generation rules
- Host integration
- Rule configuration and presets

```bash
swift test
```

## Team-Configurable Rulesets

Customize analysis rules per team or project with severity levels and thresholds:

```swift
import ArchitectCore

// Use a built-in preset
let config = RulePresets.strict

// Or create a custom configuration
let customConfig = RuleConfiguration(
    name: "My Team Rules",
    description: "Custom rules for our project",
    rules: [
        "security.force-unwrap": RuleSetting(
            enabled: true,
            severity: .error,
            parameters: [:]
        ),
        "complexity.long-function": RuleSetting(
            enabled: true,
            severity: .warning,
            parameters: ["maxLines": .int(60)]
        ),
        "naming.type-case": RuleSetting.disabled()
    ],
    globalSettings: GlobalSettings(
        minimumSeverity: .warning,
        failOnError: true,
        failOnCritical: true
    )
)

// Load from JSON file
let config = try RuleConfiguration.load(from: URL(fileURLWithPath: "ruleset.json"))

// Save to JSON
try config.save(to: URL(fileURLWithPath: "my-ruleset.json"))
```

### Built-in Presets

| Preset | Description |
|--------|-------------|
| `default` | Balanced settings for most projects |
| `strict` | All rules at higher severity, stricter thresholds |
| `lenient` | Relaxed settings for rapid development |
| `securityFocused` | Only security rules enabled |
| `swiftUIFocused` | Optimized for SwiftUI projects |
| `ci` | Configuration for CI/CD pipelines |

### Rule Registry

All rules are documented in the central registry:

```swift
// List all available rules
let allRules = RuleRegistry.shared.allRules

// Get rules by category
let securityRules = RuleRegistry.shared.rules(in: .security)

// Get rules by tag
let crashRules = RuleRegistry.shared.rules(withTag: "crash")

// Get metadata for a specific rule
if let metadata = RuleRegistry.shared.metadata(for: "complexity.long-function") {
    print(metadata.name)           // "Long Function"
    print(metadata.description)    // "Detects functions that exceed..."
    print(metadata.defaultSeverity) // .warning
    print(metadata.parameters)     // [maxLines: 50]
}
```

### Severity Levels

Configure how findings are reported:

| Level | Description |
|-------|-------------|
| `ignore` | Rule is disabled |
| `info` | Informational, no action required |
| `warning` | Should be addressed |
| `error` | Must be fixed |
| `critical` | Blocks CI/deployment |

### Example Ruleset Files

See `Examples/` for sample configurations:
- `ruleset-strict.json` - Production-ready strict rules
- `ruleset-swiftui.json` - SwiftUI-optimized configuration

## CI/CD Integration

### GitHub Actions

Use the built-in workflow or the reusable action:

```yaml
# .github/workflows/code-quality.yml
name: Code Quality

on: [pull_request]

jobs:
  analyze:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: yourorg/ArchitectTasks/.github/actions/analyze@main
        with:
          path: '.'
          policy: 'moderate'
          fail-on-findings: 'true'
          comment-on-pr: 'true'
```

The action will:
- Analyze your Swift code
- Comment findings on the PR
- Optionally fail the build if issues are found

## Automated Refactoring

Apply safe, deterministic refactoring sequences:

```swift
import ArchitectExecutor

let refactoring = AutomatedRefactoring.swiftUI()

// Fix all SwiftUI issues in a file
let result = try refactoring.fixSwiftUIView(
    findings: findings,
    source: source,
    filePath: "MyView.swift"
)

// Full refactoring pass
let result = try refactoring.fullRefactoringPass(
    findings: findings,
    source: source,
    filePath: "Complex.swift"
)

// Batch refactor multiple files
let batchResult = try refactoring.batchRefactor(files: [
    (path: "A.swift", source: sourceA, findings: findingsA),
    (path: "B.swift", source: sourceB, findings: findingsB),
])
```

## License

MIT
