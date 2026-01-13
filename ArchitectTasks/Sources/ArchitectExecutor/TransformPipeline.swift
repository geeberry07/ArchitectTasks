import Foundation
import ArchitectCore

// MARK: - Transform Pipeline

/// Orchestrates multiple transforms in dependency-aware order.
/// Prevents conflicts and tracks applied transforms.
public final class TransformPipeline: @unchecked Sendable {
    
    private var transforms: [DeterministicTransform] = []
    private var appliedTransforms: [TransformRecord] = []
    private let conflictDetector: ConflictDetector
    
    public init() {
        self.conflictDetector = ConflictDetector()
    }
    
    /// Register a transform in the pipeline
    public func register(_ transform: DeterministicTransform) {
        transforms.append(transform)
    }
    
    /// Execute a sequence of intents on source code
    public func execute(
        intents: [TaskIntent],
        source: String,
        context: TransformContext
    ) throws -> PipelineResult {
        
        var currentSource = source
        var results: [TransformRecord] = []
        var warnings: [String] = []
        
        // Sort intents by dependency order
        let orderedIntents = orderByDependency(intents)
        
        for intent in orderedIntents {
            // Find matching transform
            guard let transform = findTransform(for: intent) else {
                warnings.append("No transform found for intent: \(intent)")
                continue
            }
            
            // Check for conflicts with already applied transforms
            if let conflict = conflictDetector.detectConflict(
                intent: intent,
                appliedTransforms: results,
                source: currentSource
            ) {
                warnings.append("Skipping \(intent) due to conflict: \(conflict)")
                continue
            }
            
            // Apply transform
            do {
                let result = try transform.apply(
                    to: currentSource,
                    intent: intent,
                    context: context
                )
                
                currentSource = result.transformedSource
                
                let record = TransformRecord(
                    intent: intent,
                    transform: String(describing: type(of: transform)),
                    linesChanged: result.linesChanged,
                    diff: result.diff,
                    timestamp: Date()
                )
                
                results.append(record)
                appliedTransforms.append(record)
                
            } catch {
                warnings.append("Transform failed for \(intent): \(error.localizedDescription)")
            }
        }
        
        return PipelineResult(
            originalSource: source,
            transformedSource: currentSource,
            appliedTransforms: results,
            warnings: warnings
        )
    }
    
    /// Undo the last applied transform (if possible)
    public func undoLast() -> TransformRecord? {
        guard !appliedTransforms.isEmpty else { return nil }
        return appliedTransforms.removeLast()
    }
    
    /// Get history of applied transforms
    public var history: [TransformRecord] {
        appliedTransforms
    }
    
    /// Clear transform history
    public func clearHistory() {
        appliedTransforms.removeAll()
    }
    
    // MARK: - Private
    
    private func findTransform(for intent: TaskIntent) -> DeterministicTransform? {
        let intentKey = intentToKey(intent)
        return transforms.first { transform in
            transform.supportedIntents.contains(intentKey)
        }
    }
    
    private func intentToKey(_ intent: TaskIntent) -> String {
        switch intent {
        case .addStateObject: return "addStateObject"
        case .addBinding: return "addBinding"
        case .extractFunction: return "extractFunction"
        case .reduceNesting: return "reduceNesting"
        case .reduceParameters: return "reduceParameters"
        case .splitFile: return "splitFile"
        default: return String(describing: intent).components(separatedBy: "(").first ?? ""
        }
    }
    
    private func orderByDependency(_ intents: [TaskIntent]) -> [TaskIntent] {
        // Define transform priority (lower = earlier)
        let priority: [String: Int] = [
            "addImport": 0,           // Imports first
            "addStateObject": 1,      // Property wrappers
            "addBinding": 1,
            "extractFunction": 2,     // Structural changes
            "reduceNesting": 3,       // Refactoring
            "reduceParameters": 3,
            "splitFile": 4,           // File-level changes last
        ]
        
        return intents.sorted { a, b in
            let keyA = intentToKey(a)
            let keyB = intentToKey(b)
            return (priority[keyA] ?? 99) < (priority[keyB] ?? 99)
        }
    }
}

// MARK: - Transform Record

public struct TransformRecord: Codable, Sendable {
    public let intent: TaskIntent
    public let transform: String
    public let linesChanged: Int
    public let diff: String
    public let timestamp: Date
    
    public init(
        intent: TaskIntent,
        transform: String,
        linesChanged: Int,
        diff: String,
        timestamp: Date
    ) {
        self.intent = intent
        self.transform = transform
        self.linesChanged = linesChanged
        self.diff = diff
        self.timestamp = timestamp
    }
}

// MARK: - Pipeline Result

public struct PipelineResult: Sendable {
    public let originalSource: String
    public let transformedSource: String
    public let appliedTransforms: [TransformRecord]
    public let warnings: [String]
    
    public var totalLinesChanged: Int {
        appliedTransforms.reduce(0) { $0 + $1.linesChanged }
    }
    
    public var combinedDiff: String {
        appliedTransforms.map { $0.diff }.joined(separator: "\n")
    }
    
    public var success: Bool {
        !appliedTransforms.isEmpty
    }
}

// MARK: - Conflict Detector

final class ConflictDetector {
    
    /// Detect if applying an intent would conflict with already applied transforms
    func detectConflict(
        intent: TaskIntent,
        appliedTransforms: [TransformRecord],
        source: String
    ) -> String? {
        
        // Check for duplicate intents
        for record in appliedTransforms {
            if intentsConflict(intent, record.intent) {
                return "Already applied similar transform: \(record.intent)"
            }
        }
        
        // Check for overlapping line ranges (simplified)
        // In a real implementation, this would track exact line ranges
        
        return nil
    }
    
    private func intentsConflict(_ a: TaskIntent, _ b: TaskIntent) -> Bool {
        switch (a, b) {
        // Same property can't have multiple wrappers
        case (.addStateObject(let propA, _, _), .addStateObject(let propB, _, _)):
            return propA == propB
        case (.addBinding(let propA, _), .addBinding(let propB, _)):
            return propA == propB
        case (.addStateObject(let propA, _, _), .addBinding(let propB, _)):
            return propA == propB
        case (.addBinding(let propA, _), .addStateObject(let propB, _, _)):
            return propA == propB
            
        // Same function can't be extracted multiple times
        case (.extractFunction(let funcA, _), .extractFunction(let funcB, _)):
            return funcA == funcB
            
        default:
            return false
        }
    }
}

// MARK: - Predefined Pipelines

extension TransformPipeline {
    
    /// Create a pipeline with all built-in transforms
    public static func standard() -> TransformPipeline {
        let pipeline = TransformPipeline()
        
        // Register all transforms
        pipeline.register(SyntaxStateObjectTransform())
        pipeline.register(SyntaxBindingTransform())
        pipeline.register(SyntaxImportTransform())
        pipeline.register(GuardClauseTransform())
        pipeline.register(ExtractFunctionTransform())
        pipeline.register(RemoveUnusedImportTransform())
        
        return pipeline
    }
    
    /// Create a pipeline for SwiftUI-specific transforms
    public static func swiftUI() -> TransformPipeline {
        let pipeline = TransformPipeline()
        
        pipeline.register(SyntaxStateObjectTransform())
        pipeline.register(SyntaxBindingTransform())
        pipeline.register(SyntaxImportTransform())
        
        return pipeline
    }
    
    /// Create a pipeline for refactoring transforms
    public static func refactoring() -> TransformPipeline {
        let pipeline = TransformPipeline()
        
        pipeline.register(GuardClauseTransform())
        pipeline.register(ExtractFunctionTransform())
        pipeline.register(RemoveUnusedImportTransform())
        
        return pipeline
    }
}
