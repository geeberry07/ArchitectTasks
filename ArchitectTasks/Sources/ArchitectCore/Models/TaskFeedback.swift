import Foundation

/// Human feedback on a proposed task
public struct TaskFeedback: Codable, Sendable {
    public var decision: Decision
    public var reason: String?
    public var modifications: [Modification]
    public var timestamp: Date
    
    public init(
        decision: Decision,
        reason: String? = nil,
        modifications: [Modification] = []
    ) {
        self.decision = decision
        self.reason = reason
        self.modifications = modifications
        self.timestamp = Date()
    }
    
    // MARK: - Decision Types
    
    public enum Decision: String, Codable, Sendable {
        case approved
        case rejected
        case modified
        case deferred
    }
    
    // MARK: - Modification Types
    
    public enum Modification: Codable, Sendable {
        case narrowScope(to: TaskScope)
        case changeIntent(to: TaskIntent)
        case addStep(TaskStep)
        case removeStep(id: UUID)
        case reorderSteps(order: [UUID])
        case changeApproach(description: String)
    }
}

// MARK: - Feedback Pattern (for learning)

/// Aggregated feedback patterns used to improve task generation
public struct FeedbackPattern: Codable, Sendable {
    public var intentCategory: IntentCategory
    public var approvalRate: Double
    public var commonRejectionReasons: [String]
    public var sampleSize: Int
    public var lastUpdated: Date
    
    public init(
        intentCategory: IntentCategory,
        approvalRate: Double = 0,
        commonRejectionReasons: [String] = [],
        sampleSize: Int = 0
    ) {
        self.intentCategory = intentCategory
        self.approvalRate = approvalRate
        self.commonRejectionReasons = commonRejectionReasons
        self.sampleSize = sampleSize
        self.lastUpdated = Date()
    }
}
