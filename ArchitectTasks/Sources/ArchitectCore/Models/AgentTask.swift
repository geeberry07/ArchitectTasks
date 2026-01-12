import Foundation

/// The core unit of intelligence in the system
/// Tasks are proposed by Agent A (Planner) and executed by Agent B (Builder)
public struct AgentTask: Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var intent: TaskIntent
    public var scope: TaskScope
    public var steps: [TaskStep]
    public var status: TaskStatus
    public var requiresApproval: Bool
    public var confidenceFactors: [String: Double]
    public var createdAt: Date
    public var feedback: TaskFeedback?
    public var sourceFindings: [UUID]  // IDs of findings that generated this task
    
    public init(
        title: String,
        intent: TaskIntent,
        scope: TaskScope,
        steps: [TaskStep] = [],
        requiresApproval: Bool = true,
        sourceFindings: [UUID] = []
    ) {
        self.id = UUID()
        self.title = title
        self.intent = intent
        self.scope = scope
        self.steps = steps
        self.status = .proposed
        self.requiresApproval = requiresApproval
        self.confidenceFactors = [:]
        self.createdAt = Date()
        self.sourceFindings = sourceFindings
    }
    
    // MARK: - Computed Confidence
    
    /// Confidence is derived, not stored directly
    public var confidence: Double {
        guard !confidenceFactors.isEmpty else { return 0.5 }
        let sum = confidenceFactors.values.reduce(0, +)
        return sum / Double(confidenceFactors.count)
    }
    
    // MARK: - Task Status
    
    public enum TaskStatus: String, Codable, Sendable {
        case proposed       // Awaiting human review
        case approved       // Human approved, ready for execution
        case rejected       // Human rejected
        case inProgress     // Currently being executed
        case completed      // All steps done
        case failed         // Execution failed
        case deferred       // Postponed for later
    }
    
    // MARK: - Mutations
    
    public mutating func approve() {
        guard status == .proposed else { return }
        status = .approved
        feedback = TaskFeedback(decision: .approved)
    }
    
    public mutating func reject(reason: String) {
        guard status == .proposed else { return }
        status = .rejected
        feedback = TaskFeedback(decision: .rejected, reason: reason)
    }
    
    public mutating func markInProgress() {
        guard status == .approved else { return }
        status = .inProgress
    }
    
    public mutating func complete() {
        status = .completed
    }
    
    public mutating func fail() {
        status = .failed
    }
}
