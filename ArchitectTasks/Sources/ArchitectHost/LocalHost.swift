import Foundation
import ArchitectCore
import ArchitectAnalysis
import ArchitectPlanner
import ArchitectExecutor

/// Reference implementation of ArchitectHost for local development.
/// Can be used as CLI, embedded in apps, or as base for other hosts.
public final class LocalHost: ArchitectHost, @unchecked Sendable {
    
    public let projectRoot: URL
    public let config: HostConfig
    
    private let generator: TaskGenerator
    private let runner: TaskRunner
    private let approvalHandler: ApprovalHandler
    private let policy: ApprovalPolicy?
    private let store: (any RunStore)?
    private var observers: [HostEventObserver] = []
    
    public typealias ApprovalHandler = @Sendable (AgentTask) async -> TaskApprovalResult
    
    public init(
        projectRoot: URL,
        config: HostConfig = .default,
        policy: ApprovalPolicy? = nil,
        store: (any RunStore)? = nil,
        approvalHandler: @escaping ApprovalHandler
    ) {
        self.projectRoot = projectRoot
        self.config = config
        self.policy = policy
        self.store = store
        self.approvalHandler = approvalHandler
        
        // Initialize pipeline components
        let scanner = ProjectScanner()
        self.generator = TaskGenerator(
            scanner: scanner,
            config: config.taskConfig
        )
        self.runner = TaskRunner()
    }
    
    /// Add an observer for host events
    public func addObserver(_ observer: HostEventObserver) {
        observers.append(observer)
    }
    
    // MARK: - ArchitectHost Protocol
    
    public func analyze() async throws -> [Finding] {
        await emit(.analysisStarted(path: projectRoot.path))
        
        let findings = try await generator.analyze(projectPath: projectRoot.path)
        
        await emit(.analysisCompleted(findingCount: findings.count))
        return findings
    }
    
    public func proposeTasks(from findings: [Finding]) -> [AgentTask] {
        let tasks = generator.generateTasks(from: findings)
        
        for task in tasks {
            Task { await emit(.taskProposed(task)) }
        }
        
        return Array(tasks.prefix(config.maxTasksPerRun))
    }
    
    public func requestApproval(for task: AgentTask) async -> TaskApprovalResult {
        var mutableTask = task
        
        // Check policy first
        if let policy = policy {
            let decision = policy.evaluate(task)
            
            switch decision {
            case .allow:
                mutableTask.approve()
                await emit(.taskApproved(mutableTask))
                return TaskApprovalResult(
                    task: mutableTask,
                    decision: .approved,
                    reason: "Policy: \(policy.name)"
                )
                
            case .deny:
                mutableTask.reject(reason: "Denied by policy: \(policy.name)")
                await emit(.taskRejected(mutableTask, reason: "Policy: \(policy.name)"))
                return TaskApprovalResult(
                    task: mutableTask,
                    decision: .rejected,
                    reason: "Policy: \(policy.name)"
                )
                
            case .requireHuman:
                break // Fall through to approval handler
            }
        }
        
        // Check auto-approve threshold (legacy support)
        if shouldAutoApprove(task) {
            mutableTask.approve()
            await emit(.taskApproved(mutableTask))
            return TaskApprovalResult(task: mutableTask, decision: .approved, reason: "Auto-approved")
        }
        
        // Delegate to approval handler
        let result = await approvalHandler(task)
        
        if result.isApproved {
            await emit(.taskApproved(result.task))
        } else {
            await emit(.taskRejected(result.task, reason: result.reason))
        }
        
        return result
    }
    
    public func execute(task: AgentTask) async throws -> TaskRunResult {
        guard task.status == .approved else {
            throw HostError.taskNotApproved
        }
        
        await emit(.taskExecutionStarted(task))
        
        var mutableTask = task
        
        do {
            let result = try await runner.run(&mutableTask)
            await emit(.taskExecutionCompleted(mutableTask, result))
            return result
        } catch {
            await emit(.taskExecutionFailed(mutableTask, error))
            throw error
        }
    }
    
    public func didComplete(task: AgentTask, result: TaskRunResult) async {
        // Persist if store is available
        if let store = store {
            var run = TaskRun(task: task, projectPath: projectRoot.path)
            run.outcome = result.success ? .succeeded : .failed
            run.completedAt = Date()
            
            // Record step runs
            for stepResult in result.stepResults.values {
                if let step = task.steps.first(where: { result.stepResults[$0.id] != nil }) {
                    var stepRun = StepRun(step: step)
                    stepRun.complete(diff: stepResult.diff, linesChanged: countLines(stepResult.diff))
                    run.stepRuns.append(stepRun)
                }
            }
            
            try? await store.save(run)
        }
    }
    
    // MARK: - Convenience: Run Full Pipeline
    
    /// Run the complete analyze → propose → approve → execute pipeline
    public func run() async throws -> HostRunResult {
        let findings = try await analyze()
        let tasks = proposeTasks(from: findings)
        
        var processed = 0
        var succeeded = 0
        var results: [UUID: TaskRunResult] = [:]
        
        for task in tasks {
            processed += 1
            
            let approval = await requestApproval(for: task)
            guard approval.isApproved else { continue }
            
            do {
                let result = try await execute(task: approval.task)
                await didComplete(task: approval.task, result: result)
                
                if result.success {
                    succeeded += 1
                }
                results[task.id] = result
            } catch {
                // Continue with other tasks
            }
        }
        
        await emit(.runCompleted(tasksProcessed: processed, tasksSucceeded: succeeded))
        
        return HostRunResult(
            findings: findings,
            tasksProposed: tasks.count,
            tasksProcessed: processed,
            tasksSucceeded: succeeded,
            results: results
        )
    }
    
    // MARK: - Private
    
    private func shouldAutoApprove(_ task: AgentTask) -> Bool {
        guard config.autoApproveThreshold != .none else { return false }
        
        let taskRisk = assessRisk(task)
        return taskRisk <= config.autoApproveThreshold
    }
    
    private func assessRisk(_ task: AgentTask) -> AutoApproveLevel {
        switch task.intent.category {
        case .documentation:
            return .lowRisk
        case .quality:
            return .lowRisk
        case .dataFlow:
            return .medium
        case .structural:
            return .medium
        case .architecture:
            return .high
        }
    }
    
    private func emit(_ event: HostEvent) async {
        for observer in observers {
            await observer.handle(event: event)
        }
    }
    
    private func countLines(_ diff: String) -> Int {
        diff.components(separatedBy: "\n")
            .filter { $0.hasPrefix("+") || $0.hasPrefix("-") }
            .count
    }
}

// MARK: - Host Errors

public enum HostError: Error, Sendable {
    case taskNotApproved
    case analysisFailed
    case executionFailed(String)
}

// MARK: - Run Result

public struct HostRunResult: Sendable {
    public var findings: [Finding]
    public var tasksProposed: Int
    public var tasksProcessed: Int
    public var tasksSucceeded: Int
    public var results: [UUID: TaskRunResult]
    
    public init(
        findings: [Finding],
        tasksProposed: Int,
        tasksProcessed: Int,
        tasksSucceeded: Int,
        results: [UUID: TaskRunResult]
    ) {
        self.findings = findings
        self.tasksProposed = tasksProposed
        self.tasksProcessed = tasksProcessed
        self.tasksSucceeded = tasksSucceeded
        self.results = results
    }
    
    public var summary: String {
        """
        Findings: \(findings.count)
        Tasks proposed: \(tasksProposed)
        Tasks processed: \(tasksProcessed)
        Tasks succeeded: \(tasksSucceeded)
        """
    }
}
