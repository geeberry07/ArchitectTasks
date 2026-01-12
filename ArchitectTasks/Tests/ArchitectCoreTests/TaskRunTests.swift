import XCTest
@testable import ArchitectCore

final class TaskRunTests: XCTestCase {
    
    func testTaskRunCreation() {
        let task = AgentTask(
            title: "Test Task",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        let run = TaskRun(task: task, projectPath: "/path/to/project")
        
        XCTAssertEqual(run.task.id, task.id)
        XCTAssertEqual(run.projectPath, "/path/to/project")
        XCTAssertEqual(run.outcome, .pending)
        XCTAssertNil(run.completedAt)
        XCTAssertTrue(run.stepRuns.isEmpty)
    }
    
    func testStepRunLifecycle() {
        let step = TaskStep(
            description: "Add wrapper",
            allowedFiles: ["File.swift"],
            expectedDiffType: .addWrapper
        )
        
        var stepRun = StepRun(step: step)
        XCTAssertEqual(stepRun.status, .running)
        XCTAssertNil(stepRun.completedAt)
        
        stepRun.complete(diff: "+@StateObject var x", linesChanged: 1)
        
        XCTAssertEqual(stepRun.status, .completed)
        XCTAssertNotNil(stepRun.completedAt)
        XCTAssertEqual(stepRun.linesChanged, 1)
    }
    
    func testStepRunFailure() {
        let step = TaskStep(
            description: "Add wrapper",
            allowedFiles: ["File.swift"],
            expectedDiffType: .addWrapper
        )
        
        var stepRun = StepRun(step: step)
        stepRun.fail(error: "Property not found")
        
        XCTAssertEqual(stepRun.status, .failed)
        XCTAssertEqual(stepRun.error, "Property not found")
    }
    
    func testApprovalRecord() {
        let record = ApprovalRecord(
            decision: .approved,
            reason: "Looks good",
            approvedBy: .human,
            policyUsed: nil
        )
        
        XCTAssertEqual(record.decision, .approved)
        XCTAssertEqual(record.approvedBy, .human)
    }
    
    func testRunOutcomes() {
        XCTAssertEqual(RunOutcome.pending.rawValue, "pending")
        XCTAssertEqual(RunOutcome.succeeded.rawValue, "succeeded")
        XCTAssertEqual(RunOutcome.failed.rawValue, "failed")
    }
}
