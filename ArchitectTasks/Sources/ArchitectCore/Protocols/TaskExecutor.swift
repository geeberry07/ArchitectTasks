import Foundation

/// Protocol for Agent B (Builder) - executes approved tasks step by step
public protocol TaskExecutor: Sendable {
    /// Execute a single step within a sandbox
    func execute(step: TaskStep, in sandbox: ExecutionSandbox) async throws -> StepResult
    
    /// Validate a proposed diff before applying
    func validate(diff: String, for step: TaskStep, in sandbox: ExecutionSandbox) throws
}

// MARK: - Execution Sandbox

/// Constrains what Agent B can do during execution
public struct ExecutionSandbox: Sendable {
    public var allowedPaths: Set<String>
    public var readOnlyPaths: Set<String>
    public var maxLinesChanged: Int
    public var timeout: TimeInterval
    public var mustPassTests: Bool
    public var allowNewFiles: Bool
    
    public init(
        allowedPaths: Set<String>,
        readOnlyPaths: Set<String> = [],
        maxLinesChanged: Int = 50,
        timeout: TimeInterval = 30,
        mustPassTests: Bool = true,
        allowNewFiles: Bool = false
    ) {
        self.allowedPaths = allowedPaths
        self.readOnlyPaths = readOnlyPaths
        self.maxLinesChanged = maxLinesChanged
        self.timeout = timeout
        self.mustPassTests = mustPassTests
        self.allowNewFiles = allowNewFiles
    }
    
    /// Create a sandbox scoped to a specific step
    public static func forStep(_ step: TaskStep, scope: TaskScope) -> ExecutionSandbox {
        ExecutionSandbox(
            allowedPaths: Set(step.allowedFiles),
            readOnlyPaths: Set(scope.allowedPaths).subtracting(step.allowedFiles),
            maxLinesChanged: 50,
            timeout: 30,
            mustPassTests: true,
            allowNewFiles: step.expectedDiffType == .addFile
        )
    }
    
    /// Validate that a diff respects sandbox constraints
    public func validate(diff: String) throws {
        let lines = diff.components(separatedBy: "\n")
        let changedLines = lines.filter { $0.hasPrefix("+") || $0.hasPrefix("-") }.count
        
        guard changedLines <= maxLinesChanged else {
            throw SandboxViolation.tooManyChanges(changedLines, max: maxLinesChanged)
        }
    }
    
    /// Check if a path is allowed for modification
    public func isPathAllowed(_ path: String) -> Bool {
        allowedPaths.contains(path) || allowedPaths.contains { pattern in
            pathMatches(path, pattern: pattern)
        }
    }
    
    private func pathMatches(_ path: String, pattern: String) -> Bool {
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return path.hasPrefix(prefix)
        }
        return path == pattern
    }
}

// MARK: - Sandbox Violations

public enum SandboxViolation: Error, Sendable {
    case pathNotAllowed(String)
    case tooManyChanges(Int, max: Int)
    case timeout
    case testsFailed([String])
    case newFileNotAllowed(String)
    
    public var description: String {
        switch self {
        case .pathNotAllowed(let path):
            return "Path not allowed: \(path)"
        case .tooManyChanges(let count, let max):
            return "Too many changes: \(count) (max: \(max))"
        case .timeout:
            return "Execution timed out"
        case .testsFailed(let tests):
            return "Tests failed: \(tests.joined(separator: ", "))"
        case .newFileNotAllowed(let path):
            return "Creating new files not allowed: \(path)"
        }
    }
}
