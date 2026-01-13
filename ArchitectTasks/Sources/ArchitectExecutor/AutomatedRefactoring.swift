import Foundation
import ArchitectCore

// MARK: - Automated Refactoring

/// Orchestrates multi-intent automated refactoring sequences.
/// Applies safe, deterministic transforms in the correct order.
public final class AutomatedRefactoring: @unchecked Sendable {
    
    private let pipeline: TransformPipeline
    
    public init(pipeline: TransformPipeline = .standard()) {
        self.pipeline = pipeline
    }
    
    // MARK: - Predefined Refactoring Sequences
    
    /// Clean up a complex function: extract helpers, reduce nesting, simplify
    public func cleanupComplexFunction(
        functionName: String,
        source: String,
        filePath: String
    ) throws -> RefactoringResult {
        
        let intents: [TaskIntent] = [
            .extractFunction(from: functionName, in: filePath),
            .reduceNesting(in: filePath, at: 0),  // Will find nested code
        ]
        
        return try executeSequence(
            name: "Cleanup Complex Function",
            intents: intents,
            source: source,
            filePath: filePath
        )
    }
    
    /// Fix SwiftUI view: add missing property wrappers
    public func fixSwiftUIView(
        findings: [Finding],
        source: String,
        filePath: String
    ) throws -> RefactoringResult {
        
        let intents = findings.compactMap { finding -> TaskIntent? in
            switch finding.type {
            case .missingStateObject:
                guard let property = finding.context["property"],
                      let type = finding.context["type"] else { return nil }
                return .addStateObject(property: property, type: type, in: filePath)
                
            case .missingBinding:
                guard let property = finding.context["property"] else { return nil }
                return .addBinding(property: property, in: filePath)
                
            default:
                return nil
            }
        }
        
        return try executeSequence(
            name: "Fix SwiftUI View",
            intents: intents,
            source: source,
            filePath: filePath
        )
    }
    
    /// Clean up file: remove dead code, unused imports
    public func cleanupFile(
        source: String,
        filePath: String
    ) throws -> RefactoringResult {
        
        // For now, just remove unused imports
        // Future: add dead code removal
        let intents: [TaskIntent] = [
            .removeDeadCode(in: filePath)
        ]
        
        return try executeSequence(
            name: "Cleanup File",
            intents: intents,
            source: source,
            filePath: filePath
        )
    }
    
    /// Full refactoring pass: apply all safe transforms
    public func fullRefactoringPass(
        findings: [Finding],
        source: String,
        filePath: String
    ) throws -> RefactoringResult {
        
        var intents: [TaskIntent] = []
        
        // Group findings by type and generate intents
        for finding in findings {
            if let intent = intentFromFinding(finding, filePath: filePath) {
                intents.append(intent)
            }
        }
        
        // Filter to only safe, deterministic intents
        let safeIntents = intents.filter { isSafeForAutomation($0) }
        
        return try executeSequence(
            name: "Full Refactoring Pass",
            intents: safeIntents,
            source: source,
            filePath: filePath
        )
    }
    
    // MARK: - Execution
    
    private func executeSequence(
        name: String,
        intents: [TaskIntent],
        source: String,
        filePath: String
    ) throws -> RefactoringResult {
        
        let context = TransformContext(filePath: filePath)
        let pipelineResult = try pipeline.execute(
            intents: intents,
            source: source,
            context: context
        )
        
        return RefactoringResult(
            name: name,
            originalSource: source,
            transformedSource: pipelineResult.transformedSource,
            appliedTransforms: pipelineResult.appliedTransforms,
            skippedIntents: intents.count - pipelineResult.appliedTransforms.count,
            warnings: pipelineResult.warnings
        )
    }
    
    // MARK: - Helpers
    
    private func intentFromFinding(_ finding: Finding, filePath: String) -> TaskIntent? {
        switch finding.type {
        case .missingStateObject:
            guard let property = finding.context["property"],
                  let type = finding.context["type"] else { return nil }
            return .addStateObject(property: property, type: type, in: filePath)
            
        case .missingBinding:
            guard let property = finding.context["property"] else { return nil }
            return .addBinding(property: property, in: filePath)
            
        case .highComplexity:
            guard let metric = finding.context["metric"] else { return nil }
            switch metric {
            case "functionLines", "cyclomaticComplexity":
                guard let function = finding.context["function"] else { return nil }
                return .extractFunction(from: function, in: filePath)
            case "nestingDepth":
                return .reduceNesting(in: filePath, at: finding.location.line)
            case "parameterCount":
                guard let function = finding.context["function"] else { return nil }
                return .reduceParameters(function: function, in: filePath)
            default:
                return nil
            }
            
        case .deadCode:
            return .removeDeadCode(in: filePath)
            
        default:
            return nil
        }
    }
    
    private func isSafeForAutomation(_ intent: TaskIntent) -> Bool {
        // Only allow intents that have deterministic transforms
        switch intent {
        case .addStateObject, .addBinding:
            return true  // Property wrapper additions are safe
        case .reduceNesting:
            return false  // Guard clause transform is complex, needs review
        case .extractFunction:
            return false  // Function extraction needs human review
        case .removeDeadCode:
            return false  // Dead code removal needs review
        default:
            return false
        }
    }
}

// MARK: - Refactoring Result

public struct RefactoringResult: Sendable {
    public let name: String
    public let originalSource: String
    public let transformedSource: String
    public let appliedTransforms: [TransformRecord]
    public let skippedIntents: Int
    public let warnings: [String]
    
    public var success: Bool {
        !appliedTransforms.isEmpty
    }
    
    public var summary: String {
        """
        Refactoring: \(name)
        Applied: \(appliedTransforms.count) transform(s)
        Skipped: \(skippedIntents) intent(s)
        Warnings: \(warnings.count)
        """
    }
    
    public var diff: String {
        appliedTransforms.map { $0.diff }.joined(separator: "\n")
    }
}

// MARK: - Refactoring Presets

extension AutomatedRefactoring {
    
    /// Create a refactoring instance configured for SwiftUI projects
    public static func swiftUI() -> AutomatedRefactoring {
        AutomatedRefactoring(pipeline: .swiftUI())
    }
    
    /// Create a refactoring instance configured for general refactoring
    public static func general() -> AutomatedRefactoring {
        AutomatedRefactoring(pipeline: .refactoring())
    }
}

// MARK: - Batch Refactoring

extension AutomatedRefactoring {
    
    /// Apply refactoring to multiple files
    public func batchRefactor(
        files: [(path: String, source: String, findings: [Finding])]
    ) throws -> BatchRefactoringResult {
        
        var results: [String: RefactoringResult] = [:]
        var totalApplied = 0
        var totalSkipped = 0
        var allWarnings: [String] = []
        
        for (path, source, findings) in files {
            do {
                let result = try fullRefactoringPass(
                    findings: findings,
                    source: source,
                    filePath: path
                )
                results[path] = result
                totalApplied += result.appliedTransforms.count
                totalSkipped += result.skippedIntents
                allWarnings.append(contentsOf: result.warnings)
            } catch {
                allWarnings.append("Failed to refactor \(path): \(error.localizedDescription)")
            }
        }
        
        return BatchRefactoringResult(
            fileResults: results,
            totalTransformsApplied: totalApplied,
            totalIntentsSkipped: totalSkipped,
            warnings: allWarnings
        )
    }
}

public struct BatchRefactoringResult: Sendable {
    public let fileResults: [String: RefactoringResult]
    public let totalTransformsApplied: Int
    public let totalIntentsSkipped: Int
    public let warnings: [String]
    
    public var filesModified: Int {
        fileResults.values.filter { $0.success }.count
    }
    
    public var summary: String {
        """
        Batch Refactoring Complete
        Files modified: \(filesModified)/\(fileResults.count)
        Transforms applied: \(totalTransformsApplied)
        Intents skipped: \(totalIntentsSkipped)
        Warnings: \(warnings.count)
        """
    }
}
