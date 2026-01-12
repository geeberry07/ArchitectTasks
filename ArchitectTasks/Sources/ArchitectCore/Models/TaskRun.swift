import Foundation

// MARK: - Task Run (Persistence Unit)

/// A complete record of a task's lifecycle, from proposal to completion.
/// This is the unit of persistence and replay.
public struct TaskRun: Codable, Identifiable, Sendable {
    public var id: UUID
    public var task: AgentTask
    public var projectPath: String
    public var startedAt: Date
    public var completedAt: Date?
    public var approval: ApprovalRecord?
    public var stepRuns: [StepRun]
    public var outcome: RunOutcome
    public var metadata: [String: String]
    
    public init(
        task: AgentTask,
        projectPath: String,
        metadata: [String: String] = [:]
    ) {
        self.id = UUID()
        self.task = task
        self.projectPath = projectPath
        self.startedAt = Date()
        self.completedAt = nil
        self.approval = nil
        self.stepRuns = []
        self.outcome = .pending
        self.metadata = metadata
    }
    
    // MARK: - Computed
    
    public var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
    
    public var wasSuccessful: Bool {
        outcome == .succeeded
    }
    
    public var combinedDiff: String {
        stepRuns.compactMap(\.diff).joined(separator: "\n\n")
    }
}

// MARK: - Run Outcome

public enum RunOutcome: String, Codable, Sendable {
    case pending
    case approved
    case rejected
    case succeeded
    case failed
    case skipped
}

// MARK: - Approval Record

public struct ApprovalRecord: Codable, Sendable {
    public var decision: TaskFeedback.Decision
    public var reason: String?
    public var approvedBy: ApprovalSource
    public var timestamp: Date
    public var policyUsed: String?
    
    public init(
        decision: TaskFeedback.Decision,
        reason: String? = nil,
        approvedBy: ApprovalSource,
        policyUsed: String? = nil
    ) {
        self.decision = decision
        self.reason = reason
        self.approvedBy = approvedBy
        self.timestamp = Date()
        self.policyUsed = policyUsed
    }
}

public enum ApprovalSource: String, Codable, Sendable {
    case human
    case policy
    case autoApprove
    case ci
}

// MARK: - Step Run

public struct StepRun: Codable, Identifiable, Sendable {
    public var id: UUID
    public var stepId: UUID
    public var stepDescription: String
    public var startedAt: Date
    public var completedAt: Date?
    public var status: StepRunStatus
    public var diff: String?
    public var error: String?
    public var filesModified: [String]
    public var linesChanged: Int
    
    public init(step: TaskStep) {
        self.id = UUID()
        self.stepId = step.id
        self.stepDescription = step.description
        self.startedAt = Date()
        self.completedAt = nil
        self.status = .running
        self.diff = nil
        self.error = nil
        self.filesModified = step.allowedFiles
        self.linesChanged = 0
    }
    
    public mutating func complete(diff: String, linesChanged: Int) {
        self.completedAt = Date()
        self.status = .completed
        self.diff = diff
        self.linesChanged = linesChanged
    }
    
    public mutating func fail(error: String) {
        self.completedAt = Date()
        self.status = .failed
        self.error = error
    }
}

public enum StepRunStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case skipped
}
