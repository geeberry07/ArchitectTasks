import Foundation
import ArchitectCore

/// Orchestrates execution of an entire task
public final class TaskRunner: @unchecked Sendable {
    private let executor: TaskExecutor
    
    public init(executor: TaskExecutor = StepExecutor()) {
        self.executor = executor
    }
    
    /// Run all steps of an approved task
    public func run(_ task: inout AgentTask) async throws -> TaskRunResult {
        guard task.status == .approved else {
            throw TaskRunError.notApproved
        }
        
        task.markInProgress()
        
        var stepResults: [UUID: StepResult] = [:]
        var failedStep: UUID?
        
        for i in task.steps.indices {
            let step = task.steps[i]
            let sandbox = ExecutionSandbox.forStep(step, scope: task.scope)
            
            task.steps[i].status = .executing
            
            do {
                let result = try await executor.execute(step: step, in: sandbox)
                task.steps[i].status = .completed
                task.steps[i].result = result
                stepResults[step.id] = result
            } catch {
                task.steps[i].status = .failed
                failedStep = step.id
                
                // Mark remaining steps as skipped
                for j in (i + 1)..<task.steps.count {
                    task.steps[j].status = .skipped
                }
                
                task.fail()
                return TaskRunResult(
                    taskId: task.id,
                    success: false,
                    stepResults: stepResults,
                    failedStep: failedStep,
                    error: error.localizedDescription
                )
            }
        }
        
        task.complete()
        return TaskRunResult(
            taskId: task.id,
            success: true,
            stepResults: stepResults,
            failedStep: nil,
            error: nil
        )
    }
}

// MARK: - Result Types

public struct TaskRunResult: Sendable {
    public var taskId: UUID
    public var success: Bool
    public var stepResults: [UUID: StepResult]
    public var failedStep: UUID?
    public var error: String?
    
    /// Combined diff from all steps
    public var combinedDiff: String {
        stepResults.values
            .map(\.diff)
            .joined(separator: "\n\n")
    }
}

public enum TaskRunError: Error {
    case notApproved
    case stepFailed(UUID, String)
}
