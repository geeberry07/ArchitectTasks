import XCTest
@testable import ArchitectCore
@testable import ArchitectPlanner
@testable import ArchitectAnalysis

final class TaskGeneratorTests: XCTestCase {
    
    func testGenerateTaskFromFinding() {
        let finding = Finding(
            type: .missingStateObject,
            location: SourceLocation(file: "ProfileView.swift", line: 10),
            severity: .error, // Higher severity for better confidence
            context: [
                "property": "viewModel",
                "type": "ProfileViewModel",
                "view": "ProfileView"
            ],
            message: "Property 'viewModel' may need @StateObject"
        )
        
        // Use lower confidence threshold for test
        let config = TaskGenerationConfig(minimumConfidence: 0.5)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        XCTAssertEqual(task.status, .proposed)
        XCTAssertTrue(task.requiresApproval)
        XCTAssertFalse(task.steps.isEmpty)
        XCTAssertEqual(task.sourceFindings, [finding.id])
        
        // Check intent
        if case .addStateObject(let property, let type, let file) = task.intent {
            XCTAssertEqual(property, "viewModel")
            XCTAssertEqual(type, "ProfileViewModel")
            XCTAssertEqual(file, "ProfileView.swift")
        } else {
            XCTFail("Expected addStateObject intent")
        }
    }
    
    func testConfidenceFiltering() {
        let finding = Finding(
            type: .missingStateObject,
            location: SourceLocation(file: "Test.swift"),
            severity: .info, // Low severity = lower confidence
            context: [:],    // Empty context = lower confidence
            message: "Test"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.9)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        // Should be filtered out due to low confidence
        XCTAssertTrue(tasks.isEmpty)
    }
    
    func testMaxTasksLimit() {
        let findings = (0..<20).map { i in
            Finding(
                type: .missingStateObject,
                location: SourceLocation(file: "View\(i).swift", line: 1),
                severity: .warning,
                context: ["property": "vm", "type": "VM", "view": "View\(i)"],
                message: "Test \(i)"
            )
        }
        
        let config = TaskGenerationConfig(
            minimumConfidence: 0.0,
            maxTasksPerRun: 5
        )
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: findings)
        
        XCTAssertEqual(tasks.count, 5)
    }
    
    func testIntentCategoryFiltering() {
        let finding = Finding(
            type: .missingStateObject,
            location: SourceLocation(file: "Test.swift"),
            severity: .warning,
            context: ["property": "vm", "type": "VM", "view": "Test"],
            message: "Test"
        )
        
        // Disable dataFlow category
        let config = TaskGenerationConfig(
            minimumConfidence: 0.0,
            enabledIntentCategories: [.structural, .quality]
        )
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        // addStateObject is dataFlow, should be filtered
        XCTAssertTrue(tasks.isEmpty)
    }
}


// MARK: - Complexity Rule Tests

extension TaskGeneratorTests {
    
    func testGenerateTaskFromLongFunctionFinding() {
        let finding = Finding(
            type: .highComplexity,
            location: SourceLocation(file: "Service.swift", line: 25),
            severity: .warning,
            context: [
                "metric": "functionLines",
                "function": "processData",
                "value": "120",
                "threshold": "50"
            ],
            message: "Function 'processData' has 120 lines (threshold: 50)"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.0)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        if case .extractFunction(let from, let file) = task.intent {
            XCTAssertEqual(from, "processData")
            XCTAssertEqual(file, "Service.swift")
        } else {
            XCTFail("Expected extractFunction intent, got \(task.intent)")
        }
        
        XCTAssertEqual(task.intent.category, .quality)
    }
    
    func testGenerateTaskFromDeepNestingFinding() {
        let finding = Finding(
            type: .highComplexity,
            location: SourceLocation(file: "Handler.swift", line: 42),
            severity: .warning,
            context: [
                "metric": "nestingDepth",
                "value": "6",
                "threshold": "4"
            ],
            message: "Nesting depth 6 exceeds threshold 4"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.0)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        if case .reduceNesting(let file, let line) = task.intent {
            XCTAssertEqual(file, "Handler.swift")
            XCTAssertEqual(line, 42)
        } else {
            XCTFail("Expected reduceNesting intent, got \(task.intent)")
        }
    }
    
    func testGenerateTaskFromTooManyParametersFinding() {
        let finding = Finding(
            type: .highComplexity,
            location: SourceLocation(file: "API.swift", line: 15),
            severity: .warning,
            context: [
                "metric": "parameterCount",
                "function": "createRequest",
                "value": "8",
                "threshold": "5"
            ],
            message: "Function 'createRequest' has 8 parameters (threshold: 5)"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.0)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        if case .reduceParameters(let function, let file) = task.intent {
            XCTAssertEqual(function, "createRequest")
            XCTAssertEqual(file, "API.swift")
        } else {
            XCTFail("Expected reduceParameters intent, got \(task.intent)")
        }
    }
    
    func testGenerateTaskFromLargeFileFinding() {
        let finding = Finding(
            type: .highComplexity,
            location: SourceLocation(file: "Monolith.swift", line: 1),
            severity: .warning,
            context: [
                "metric": "fileLines",
                "value": "800",
                "threshold": "500"
            ],
            message: "File has 800 lines (threshold: 500)"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.0)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        if case .splitFile(let path) = task.intent {
            XCTAssertEqual(path, "Monolith.swift")
        } else {
            XCTFail("Expected splitFile intent, got \(task.intent)")
        }
    }
    
    func testGenerateTaskFromHighCyclomaticComplexityFinding() {
        let finding = Finding(
            type: .highComplexity,
            location: SourceLocation(file: "Parser.swift", line: 50),
            severity: .warning,
            context: [
                "metric": "cyclomaticComplexity",
                "function": "parseToken",
                "value": "15",
                "threshold": "10"
            ],
            message: "Function 'parseToken' has cyclomatic complexity 15 (threshold: 10)"
        )
        
        let config = TaskGenerationConfig(minimumConfidence: 0.0)
        let generator = TaskGenerator(config: config)
        let tasks = generator.generateTasks(from: [finding])
        
        XCTAssertEqual(tasks.count, 1)
        
        let task = tasks[0]
        if case .extractFunction(let from, let file) = task.intent {
            XCTAssertEqual(from, "parseToken")
            XCTAssertEqual(file, "Parser.swift")
        } else {
            XCTFail("Expected extractFunction intent, got \(task.intent)")
        }
    }
}
