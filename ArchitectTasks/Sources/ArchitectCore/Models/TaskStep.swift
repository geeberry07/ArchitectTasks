import Foundation

/// A single atomic step within a task
public struct TaskStep: Codable, Identifiable, Sendable {
    public var id: UUID
    public var description: String
    public var allowedFiles: [String]
    public var expectedDiffType: DiffType
    public var status: StepStatus
    public var result: StepResult?
    
    public init(
        description: String,
        allowedFiles: [String],
        expectedDiffType: DiffType
    ) {
        self.id = UUID()
        self.description = description
        self.allowedFiles = allowedFiles
        self.expectedDiffType = expectedDiffType
        self.status = .pending
        self.result = nil
    }
    
    // MARK: - Diff Types
    
    public enum DiffType: String, Codable, Sendable {
        case addProperty
        case addMethod
        case addImport
        case modifyBody
        case addFile
        case deleteLines
        case renameSymbol
        case addWrapper      // e.g., wrap with @StateObject
        case addType         // e.g., add struct/class/enum
    }
    
    // MARK: - Step Status
    
    public enum StepStatus: String, Codable, Sendable {
        case pending
        case executing
        case completed
        case failed
        case skipped
    }
}

// MARK: - Step Result

public struct StepResult: Codable, Sendable {
    public var diff: String
    public var testsRan: Bool
    public var testsPassed: Bool
    public var warnings: [String]
    public var executionTime: TimeInterval
    
    public init(
        diff: String,
        testsRan: Bool = false,
        testsPassed: Bool = true,
        warnings: [String] = [],
        executionTime: TimeInterval = 0
    ) {
        self.diff = diff
        self.testsRan = testsRan
        self.testsPassed = testsPassed
        self.warnings = warnings
        self.executionTime = executionTime
    }
}
