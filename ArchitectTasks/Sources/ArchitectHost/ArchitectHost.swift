import Foundation
import ArchitectCore

// MARK: - Host Protocol

/// Contract for any system that drives the ArchitectTasks pipeline.
/// Implementations: CLI, menu bar app, Xcode plugin, CI bot, etc.
public protocol ArchitectHost: Sendable {
    
    /// The root path this host operates on
    var projectRoot: URL { get }
    
    /// Configuration for this host
    var config: HostConfig { get }
    
    /// Analyze the project and return findings
    func analyze() async throws -> [Finding]
    
    /// Generate tasks from findings
    func proposeTasks(from findings: [Finding]) -> [AgentTask]
    
    /// Present a task for human approval
    /// Returns the task with updated status (approved/rejected/modified)
    func requestApproval(for task: AgentTask) async -> TaskApprovalResult
    
    /// Execute an approved task
    func execute(task: AgentTask) async throws -> TaskRunResult
    
    /// Called when a task completes (for persistence, logging, etc.)
    func didComplete(task: AgentTask, result: TaskRunResult) async
}

// MARK: - Host Configuration

public struct HostConfig: Sendable {
    /// Which analyzers to run
    public var enabledAnalyzers: Set<String>
    
    /// Task generation settings
    public var taskConfig: TaskGenerationConfig
    
    /// Auto-approve tasks below this risk level
    public var autoApproveThreshold: AutoApproveLevel
    
    /// Maximum tasks to process per run
    public var maxTasksPerRun: Int
    
    /// Whether to actually apply diffs (false = dry run)
    public var applyChanges: Bool
    
    /// Paths to exclude from analysis
    public var excludedPaths: [String]
    
    public init(
        enabledAnalyzers: Set<String> = ["SwiftUIBindingAnalyzer"],
        taskConfig: TaskGenerationConfig = .default,
        autoApproveThreshold: AutoApproveLevel = .none,
        maxTasksPerRun: Int = 10,
        applyChanges: Bool = false,
        excludedPaths: [String] = [".build", "DerivedData", ".git", "Pods"]
    ) {
        self.enabledAnalyzers = enabledAnalyzers
        self.taskConfig = taskConfig
        self.autoApproveThreshold = autoApproveThreshold
        self.maxTasksPerRun = maxTasksPerRun
        self.applyChanges = applyChanges
        self.excludedPaths = excludedPaths
    }
    
    public static let `default` = HostConfig()
    
    /// For CI/automated runs
    public static let ci = HostConfig(
        autoApproveThreshold: .none,
        applyChanges: false
    )
    
    /// For interactive development
    public static let interactive = HostConfig(
        autoApproveThreshold: .lowRisk,
        applyChanges: true
    )
}

// MARK: - Auto-Approve Levels

public enum AutoApproveLevel: Int, Sendable, Comparable {
    case none = 0           // Always require approval
    case lowRisk = 1        // Auto-approve documentation, comments
    case medium = 2         // Auto-approve single-file changes
    case high = 3           // Auto-approve most things (dangerous)
    
    public static func < (lhs: AutoApproveLevel, rhs: AutoApproveLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Approval Result

public struct TaskApprovalResult: Sendable {
    public var task: AgentTask
    public var decision: TaskFeedback.Decision
    public var reason: String?
    
    public init(task: AgentTask, decision: TaskFeedback.Decision, reason: String? = nil) {
        self.task = task
        self.decision = decision
        self.reason = reason
    }
    
    public var isApproved: Bool {
        decision == .approved || decision == .modified
    }
}

// MARK: - Host Events (for logging/observability)

public enum HostEvent: Sendable {
    case analysisStarted(path: String)
    case analysisCompleted(findingCount: Int)
    case taskProposed(AgentTask)
    case taskApproved(AgentTask)
    case taskRejected(AgentTask, reason: String?)
    case taskExecutionStarted(AgentTask)
    case taskExecutionCompleted(AgentTask, TaskRunResult)
    case taskExecutionFailed(AgentTask, Error)
    case runCompleted(tasksProcessed: Int, tasksSucceeded: Int)
}

/// Observer for host events
public protocol HostEventObserver: Sendable {
    func handle(event: HostEvent) async
}
