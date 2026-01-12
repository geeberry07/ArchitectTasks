import XCTest
@testable import ArchitectCore

final class AgentTaskTests: XCTestCase {
    
    func testTaskCreation() {
        let task = AgentTask(
            title: "Add StateObject to ProfileView",
            intent: .addStateObject(property: "viewModel", type: "ProfileViewModel", in: "ProfileView.swift"),
            scope: .file(path: "ProfileView.swift")
        )
        
        XCTAssertEqual(task.status, .proposed)
        XCTAssertTrue(task.requiresApproval)
        XCTAssertEqual(task.confidence, 0.5) // Default when no factors
    }
    
    func testTaskApproval() {
        var task = AgentTask(
            title: "Test Task",
            intent: .addBinding(property: "value", in: "TestView.swift"),
            scope: .file(path: "TestView.swift")
        )
        
        task.approve()
        
        XCTAssertEqual(task.status, .approved)
        XCTAssertEqual(task.feedback?.decision, .approved)
    }
    
    func testTaskRejection() {
        var task = AgentTask(
            title: "Test Task",
            intent: .addBinding(property: "value", in: "TestView.swift"),
            scope: .file(path: "TestView.swift")
        )
        
        task.reject(reason: "Not needed")
        
        XCTAssertEqual(task.status, .rejected)
        XCTAssertEqual(task.feedback?.decision, .rejected)
        XCTAssertEqual(task.feedback?.reason, "Not needed")
    }
    
    func testConfidenceCalculation() {
        var task = AgentTask(
            title: "Test Task",
            intent: .addBinding(property: "value", in: "TestView.swift"),
            scope: .file(path: "TestView.swift")
        )
        
        task.confidenceFactors = [
            "rulePrecision": 0.8,
            "severityWeight": 0.6,
            "contextCompleteness": 1.0
        ]
        
        XCTAssertEqual(task.confidence, 0.8, accuracy: 0.01)
    }
    
    func testTaskSteps() {
        let steps = [
            TaskStep(
                description: "Locate property",
                allowedFiles: ["View.swift"],
                expectedDiffType: .modifyBody
            ),
            TaskStep(
                description: "Add wrapper",
                allowedFiles: ["View.swift"],
                expectedDiffType: .addWrapper
            )
        ]
        
        let task = AgentTask(
            title: "Test Task",
            intent: .addBinding(property: "value", in: "View.swift"),
            scope: .file(path: "View.swift"),
            steps: steps
        )
        
        XCTAssertEqual(task.steps.count, 2)
        XCTAssertEqual(task.steps[0].status, .pending)
    }
}
