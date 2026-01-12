import Foundation
import ArchitectCore

/// Agent B: Executes approved tasks step by step
/// This is a deterministic executor - no LLM, just syntax transforms
public final class StepExecutor: TaskExecutor, @unchecked Sendable {
    private let transforms: [TaskStep.DiffType: StepTransform]
    
    public init(transforms: [TaskStep.DiffType: StepTransform] = StepTransform.defaults) {
        self.transforms = transforms
    }
    
    // MARK: - TaskExecutor Protocol
    
    public func execute(step: TaskStep, in sandbox: ExecutionSandbox) async throws -> StepResult {
        let startTime = Date()
        
        // Validate sandbox allows this step
        for file in step.allowedFiles {
            guard sandbox.isPathAllowed(file) else {
                throw SandboxViolation.pathNotAllowed(file)
            }
        }
        
        // Get the appropriate transform
        guard let transform = transforms[step.expectedDiffType] else {
            return StepResult(
                diff: "// No transform available for \(step.expectedDiffType)",
                testsRan: false,
                testsPassed: true,
                warnings: ["No transform registered for diff type: \(step.expectedDiffType)"],
                executionTime: Date().timeIntervalSince(startTime)
            )
        }
        
        // Execute the transform
        let diff = try transform.execute(step)
        
        // Validate the diff
        try sandbox.validate(diff: diff)
        
        return StepResult(
            diff: diff,
            testsRan: false,
            testsPassed: true,
            warnings: [],
            executionTime: Date().timeIntervalSince(startTime)
        )
    }
    
    public func validate(diff: String, for step: TaskStep, in sandbox: ExecutionSandbox) throws {
        try sandbox.validate(diff: diff)
    }
}

// MARK: - Step Transform

/// A deterministic code transformation
public struct StepTransform: Sendable {
    public var diffType: TaskStep.DiffType
    public var execute: @Sendable (TaskStep) throws -> String
    
    public init(
        diffType: TaskStep.DiffType,
        execute: @escaping @Sendable (TaskStep) throws -> String
    ) {
        self.diffType = diffType
        self.execute = execute
    }
}

extension StepTransform {
    
    public static let defaults: [TaskStep.DiffType: StepTransform] = [
        .addWrapper: addWrapperTransform,
        .addProperty: addPropertyTransform,
        .addImport: addImportTransform
    ]
    
    /// Transform to add a property wrapper
    public static let addWrapperTransform = StepTransform(diffType: .addWrapper) { step in
        // This produces a diff template - actual application would use SwiftSyntax
        """
        --- a/\(step.allowedFiles.first ?? "file.swift")
        +++ b/\(step.allowedFiles.first ?? "file.swift")
        @@ -1,1 +1,1 @@
        -    var viewModel: ViewModel
        +    @StateObject var viewModel: ViewModel
        """
    }
    
    /// Transform to add a property
    public static let addPropertyTransform = StepTransform(diffType: .addProperty) { step in
        """
        --- a/\(step.allowedFiles.first ?? "file.swift")
        +++ b/\(step.allowedFiles.first ?? "file.swift")
        @@ -1,0 +1,1 @@
        +    @StateObject var viewModel = ViewModel()
        """
    }
    
    /// Transform to add an import
    public static let addImportTransform = StepTransform(diffType: .addImport) { step in
        """
        --- a/\(step.allowedFiles.first ?? "file.swift")
        +++ b/\(step.allowedFiles.first ?? "file.swift")
        @@ -1,0 +1,1 @@
        +import SwiftUI
        """
    }
}
