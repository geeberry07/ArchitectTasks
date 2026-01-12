import Foundation

/// Protocol for Agent A (Planner) - analyzes code and generates tasks
public protocol TaskEmitter: Sendable {
    /// Analyze a project and produce findings
    func analyze(projectPath: String) async throws -> [Finding]
    
    /// Generate tasks from findings
    func generateTasks(from findings: [Finding]) -> [AgentTask]
}

/// Configuration for task generation
public struct TaskGenerationConfig: Sendable {
    public var minimumConfidence: Double
    public var maxTasksPerRun: Int
    public var enabledIntentCategories: Set<IntentCategory>
    public var requireApprovalForCategories: Set<IntentCategory>
    
    public init(
        minimumConfidence: Double = 0.6,
        maxTasksPerRun: Int = 10,
        enabledIntentCategories: Set<IntentCategory> = Set(IntentCategory.allCases),
        requireApprovalForCategories: Set<IntentCategory> = Set(IntentCategory.allCases)
    ) {
        self.minimumConfidence = minimumConfidence
        self.maxTasksPerRun = maxTasksPerRun
        self.enabledIntentCategories = enabledIntentCategories
        self.requireApprovalForCategories = requireApprovalForCategories
    }
    
    public static let `default` = TaskGenerationConfig()
}

extension IntentCategory: CaseIterable {
    public static var allCases: [IntentCategory] {
        [.structural, .dataFlow, .quality, .architecture, .documentation]
    }
}
