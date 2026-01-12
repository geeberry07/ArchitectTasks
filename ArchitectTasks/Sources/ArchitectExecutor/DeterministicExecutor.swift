import Foundation
import ArchitectCore

// MARK: - Deterministic Executor

/// An executor that uses only deterministic transforms.
/// No LLMs, no heuristics - pure syntax rewriting.
public final class DeterministicExecutor: TaskExecutor, @unchecked Sendable {
    
    private let registry: TransformRegistry
    private let fileManager: FileManager
    
    public init(registry: TransformRegistry = .shared) {
        self.registry = registry
        self.fileManager = .default
    }
    
    // MARK: - TaskExecutor Protocol
    
    public func execute(step: TaskStep, in sandbox: ExecutionSandbox) async throws -> StepResult {
        let startTime = Date()
        
        // Validate sandbox
        for file in step.allowedFiles {
            guard sandbox.isPathAllowed(file) else {
                throw SandboxViolation.pathNotAllowed(file)
            }
        }
        
        // For now, return a placeholder - real execution needs file I/O
        return StepResult(
            diff: "// Deterministic executor ready",
            testsRan: false,
            testsPassed: true,
            warnings: [],
            executionTime: Date().timeIntervalSince(startTime)
        )
    }
    
    public func validate(diff: String, for step: TaskStep, in sandbox: ExecutionSandbox) throws {
        try sandbox.validate(diff: diff)
    }
    
    // MARK: - Direct Transform Execution
    
    /// Execute a transform directly on source code (for testing/preview)
    public func executeTransform(
        intent: TaskIntent,
        source: String,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard let transform = registry.transform(for: intent) else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        return try transform.apply(to: source, intent: intent, context: context)
    }
    
    /// Execute a transform on a file
    public func executeTransformOnFile(
        intent: TaskIntent,
        filePath: String,
        sandbox: ExecutionSandbox,
        applyChanges: Bool = false
    ) throws -> TransformResult {
        
        // Validate sandbox
        guard sandbox.isPathAllowed(filePath) else {
            throw SandboxViolation.pathNotAllowed(filePath)
        }
        
        // Read file
        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        
        // Extract context from intent
        let context = extractContext(from: intent, filePath: filePath)
        
        // Execute transform
        let result = try executeTransform(intent: intent, source: source, context: context)
        
        // Validate diff
        try sandbox.validate(diff: result.diff)
        
        // Apply changes if requested
        if applyChanges && result.hasChanges {
            try result.transformedSource.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        
        return result
    }
    
    // MARK: - Private
    
    private func extractContext(from intent: TaskIntent, filePath: String) -> TransformContext {
        switch intent {
        case .addStateObject(let property, let type, _):
            return TransformContext(
                filePath: filePath,
                propertyName: property,
                typeName: type
            )
        case .addBinding(let property, _):
            return TransformContext(
                filePath: filePath,
                propertyName: property
            )
        default:
            return TransformContext(filePath: filePath)
        }
    }
}

// MARK: - Executor Factory

/// Creates the appropriate executor based on configuration
public enum ExecutorFactory {
    
    public enum ExecutorType {
        case deterministic  // Only deterministic transforms
        case template       // Template-based (current default)
        case hybrid         // Try deterministic first, fall back to template
    }
    
    public static func create(type: ExecutorType = .deterministic) -> TaskExecutor {
        switch type {
        case .deterministic:
            return DeterministicExecutor()
        case .template:
            return StepExecutor()
        case .hybrid:
            return HybridExecutor()
        }
    }
}

// MARK: - Hybrid Executor

/// Tries deterministic transforms first, falls back to templates
public final class HybridExecutor: TaskExecutor, @unchecked Sendable {
    
    private let deterministic: DeterministicExecutor
    private let template: StepExecutor
    
    public init() {
        self.deterministic = DeterministicExecutor()
        self.template = StepExecutor()
    }
    
    public func execute(step: TaskStep, in sandbox: ExecutionSandbox) async throws -> StepResult {
        // Try deterministic first
        do {
            return try await deterministic.execute(step: step, in: sandbox)
        } catch TransformError.unsupportedIntent {
            // Fall back to template
            return try await template.execute(step: step, in: sandbox)
        }
    }
    
    public func validate(diff: String, for step: TaskStep, in sandbox: ExecutionSandbox) throws {
        try sandbox.validate(diff: diff)
    }
}
