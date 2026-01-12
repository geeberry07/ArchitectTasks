import XCTest
@testable import ArchitectHost
@testable import ArchitectCore

final class LocalHostTests: XCTestCase {
    
    func testHostConfigDefaults() {
        let config = HostConfig.default
        
        XCTAssertEqual(config.autoApproveThreshold, .none)
        XCTAssertFalse(config.applyChanges)
        XCTAssertEqual(config.maxTasksPerRun, 10)
    }
    
    func testAutoApproveLevelComparison() {
        XCTAssertTrue(AutoApproveLevel.none < AutoApproveLevel.lowRisk)
        XCTAssertTrue(AutoApproveLevel.lowRisk < AutoApproveLevel.medium)
        XCTAssertTrue(AutoApproveLevel.medium < AutoApproveLevel.high)
    }
    
    func testTaskApprovalResult() {
        let task = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "Test.swift"),
            scope: .file(path: "Test.swift")
        )
        
        let approved = TaskApprovalResult(task: task, decision: .approved)
        XCTAssertTrue(approved.isApproved)
        
        let rejected = TaskApprovalResult(task: task, decision: .rejected, reason: "Not needed")
        XCTAssertFalse(rejected.isApproved)
        XCTAssertEqual(rejected.reason, "Not needed")
        
        let modified = TaskApprovalResult(task: task, decision: .modified)
        XCTAssertTrue(modified.isApproved)
    }
    
    func testHostRunResultSummary() {
        let result = HostRunResult(
            findings: [
                Finding(
                    type: .missingStateObject,
                    location: SourceLocation(file: "Test.swift"),
                    message: "Test"
                )
            ],
            tasksProposed: 3,
            tasksProcessed: 2,
            tasksSucceeded: 1,
            results: [:]
        )
        
        let summary = result.summary
        XCTAssertTrue(summary.contains("Findings: 1"))
        XCTAssertTrue(summary.contains("Tasks proposed: 3"))
        XCTAssertTrue(summary.contains("Tasks processed: 2"))
        XCTAssertTrue(summary.contains("Tasks succeeded: 1"))
    }
    
    func testLocalHostCreation() async {
        let url = URL(fileURLWithPath: "/tmp/test-project")
        
        let host = LocalHost(
            projectRoot: url,
            config: .default,
            approvalHandler: { task in
                TaskApprovalResult(task: task, decision: .approved)
            }
        )
        
        XCTAssertEqual(host.projectRoot, url)
        XCTAssertEqual(host.config.autoApproveThreshold, .none)
    }
}
