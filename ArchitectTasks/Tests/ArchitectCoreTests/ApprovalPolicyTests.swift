import XCTest
@testable import ArchitectCore

final class ApprovalPolicyTests: XCTestCase {
    
    func testPolicyAllowsDocumentation() {
        let policy = ApprovalPolicy.conservative
        
        let task = AgentTask(
            title: "Document API",
            intent: .documentPublicAPI(in: "API.swift"),
            scope: .file(path: "API.swift")
        )
        
        let decision = policy.evaluate(task)
        XCTAssertEqual(decision, .allow)
    }
    
    func testPolicyDeniesArchitecture() {
        let policy = ApprovalPolicy.conservative
        
        let task = AgentTask(
            title: "Refactor to protocol",
            intent: .refactorToProtocol(concrete: "UserService"),
            scope: .module(name: "Services")
        )
        
        let decision = policy.evaluate(task)
        XCTAssertEqual(decision, .deny)
    }
    
    func testPolicyRequiresHumanForDataFlow() {
        let policy = ApprovalPolicy.conservative
        
        let task = AgentTask(
            title: "Add StateObject",
            intent: .addStateObject(property: "vm", type: "ViewModel", in: "View.swift"),
            scope: .file(path: "View.swift")
        )
        
        let decision = policy.evaluate(task)
        XCTAssertEqual(decision, .requireHuman)
    }
    
    func testModeratePolicy() {
        let policy = ApprovalPolicy.moderate
        
        // High confidence, single file, few steps = allow
        var task = AgentTask(
            title: "Add binding",
            intent: .addBinding(property: "value", in: "View.swift"),
            scope: .file(path: "View.swift"),
            steps: [
                TaskStep(description: "Step 1", allowedFiles: ["View.swift"], expectedDiffType: .addWrapper)
            ]
        )
        task.confidenceFactors = ["test": 0.9]
        
        let decision = policy.evaluate(task)
        XCTAssertEqual(decision, .allow)
    }
    
    func testConditionIntentCategory() {
        let condition = PolicyCondition.intentCategory(.documentation)
        
        let docTask = AgentTask(
            title: "Doc",
            intent: .documentPublicAPI(in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        let dataTask = AgentTask(
            title: "Data",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        XCTAssertTrue(condition.matches(docTask))
        XCTAssertFalse(condition.matches(dataTask))
    }
    
    func testConditionConfidence() {
        var task = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        task.confidenceFactors = ["test": 0.8]
        
        let above = PolicyCondition.confidenceAbove(0.7)
        let below = PolicyCondition.confidenceBelow(0.9)
        
        XCTAssertTrue(above.matches(task))
        XCTAssertTrue(below.matches(task))
        XCTAssertFalse(PolicyCondition.confidenceAbove(0.9).matches(task))
    }
    
    func testConditionAll() {
        var task = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift"),
            steps: [TaskStep(description: "1", allowedFiles: [], expectedDiffType: .addWrapper)]
        )
        task.confidenceFactors = ["test": 0.9]
        
        let condition = PolicyCondition.all([
            .scopeType(.file),
            .confidenceAbove(0.8),
            .maxSteps(3)
        ])
        
        XCTAssertTrue(condition.matches(task))
    }
    
    func testConditionAny() {
        let task = AgentTask(
            title: "Test",
            intent: .documentPublicAPI(in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        let condition = PolicyCondition.any([
            .intentCategory(.documentation),
            .intentCategory(.quality)
        ])
        
        XCTAssertTrue(condition.matches(task))
    }
    
    func testConditionNot() {
        let task = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        let condition = PolicyCondition.not(.intentCategory(.architecture))
        
        XCTAssertTrue(condition.matches(task))
    }
    
    func testCustomPolicy() {
        let policy = ApprovalPolicy(
            name: "Custom",
            rules: [
                PolicyRule(
                    condition: .filePattern("*Tests.swift"),
                    decision: .allow,
                    reason: "Test files are safe"
                ),
                PolicyRule(
                    condition: .scopeType(.project),
                    decision: .deny,
                    reason: "No project-wide changes"
                )
            ],
            defaultDecision: .requireHuman
        )
        
        let testTask = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "ViewTests.swift"),
            scope: .file(path: "ViewTests.swift")
        )
        
        let projectTask = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "View.swift"),
            scope: .project
        )
        
        XCTAssertEqual(policy.evaluate(testTask), .allow)
        XCTAssertEqual(policy.evaluate(projectTask), .deny)
    }
}
