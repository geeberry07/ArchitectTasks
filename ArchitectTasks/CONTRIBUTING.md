# Contributing to ArchitectTasks

Thank you for your interest in contributing to ArchitectTasks!

## Development Setup

```bash
# Clone the repository
git clone https://github.com/yourorg/ArchitectTasks.git
cd ArchitectTasks

# Build
swift build

# Run tests
swift test

# Run the CLI
swift run architect-cli help
```

## Project Structure

```
ArchitectTasks/
├── Sources/
│   ├── ArchitectCore/       # Models, protocols, persistence (no deps)
│   ├── ArchitectAnalysis/   # SwiftSyntax-based analyzers
│   ├── ArchitectPlanner/    # Task generation (Agent A)
│   ├── ArchitectExecutor/   # Deterministic transforms (Agent B)
│   ├── ArchitectHost/       # Host contract + LocalHost
│   └── architect-cli/       # CLI executable
├── Tests/
├── Package.swift
└── README.md
```

## Adding a New Analyzer

1. Create a new file in `Sources/ArchitectAnalysis/Analyzers/`
2. Implement the `Analyzer` protocol:

```swift
struct MyAnalyzer: Analyzer {
    var supportedFindingTypes: [Finding.FindingType] { [.myFindingType] }
    
    func analyze(fileAt path: String, content: String) throws -> [Finding] {
        // Your analysis logic
    }
}
```

3. Add the finding type to `Finding.FindingType` if needed
4. Register in `ProjectScanner` or allow users to configure

## Adding a New Transform

1. Create a new file in `Sources/ArchitectExecutor/Transforms/`
2. Implement the `DeterministicTransform` protocol:

```swift
struct MyTransform: DeterministicTransform {
    var supportedIntents: [String] { ["myIntent"] }
    
    func apply(to source: String, intent: TaskIntent, context: TransformContext) throws -> TransformResult {
        // Pure, deterministic transformation
    }
}
```

3. Register in `TransformRegistry.registerBuiltins()`
4. Add tests

## Guidelines

### Code Style

- Follow Swift API Design Guidelines
- Use `// MARK: -` for section organization
- Keep functions focused and testable
- Prefer value types (structs/enums) over classes

### Testing

- All new features must have tests
- Aim for deterministic, fast tests
- Use `InMemoryRunStore` for persistence tests

### Commits

- Use conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`
- Keep commits focused and atomic
- Reference issues when applicable

### Pull Requests

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run `swift test` to ensure all tests pass
5. Submit a PR with a clear description

## Architecture Principles

1. **Tasks are the unit of intelligence** - not files, not diffs
2. **Planner/Executor split** - Agent A proposes, Agent B executes
3. **Deterministic transforms** - no LLMs in the execution path
4. **Policy-driven approval** - declarative, not procedural
5. **Persistence for auditability** - every run is recorded

## Questions?

Open an issue for discussion before starting major work.
