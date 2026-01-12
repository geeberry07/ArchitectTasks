import XCTest
@testable import ArchitectCore

final class PolicySchemaTests: XCTestCase {
    
    func testSchemaToPolicy() throws {
        let schema = PolicySchema(
            name: "Test Policy",
            description: "A test policy",
            version: "1.0",
            rules: [
                RuleSchema(
                    condition: ConditionSchema(type: "intentCategory", value: .string("documentation")),
                    decision: "allow",
                    reason: "Docs are safe"
                ),
                RuleSchema(
                    condition: ConditionSchema(type: "intentCategory", value: .string("architecture")),
                    decision: "deny",
                    reason: "Arch needs review"
                )
            ],
            defaultDecision: "requireHuman"
        )
        
        let policy = try schema.toPolicy()
        
        XCTAssertEqual(policy.name, "Test Policy")
        XCTAssertEqual(policy.rules.count, 2)
        XCTAssertEqual(policy.defaultDecision, .requireHuman)
    }
    
    func testPolicyToSchema() throws {
        let policy = ApprovalPolicy.moderate
        let schema = policy.toSchema()
        
        XCTAssertEqual(schema.name, "Moderate")
        XCTAssertFalse(schema.rules.isEmpty)
    }
    
    func testPolicyRoundTrip() throws {
        let original = ApprovalPolicy.conservative
        let json = try original.toJSON()
        let schema = try JSONDecoder().decode(PolicySchema.self, from: json)
        let restored = try schema.toPolicy()
        
        XCTAssertEqual(original.name, restored.name)
        XCTAssertEqual(original.rules.count, restored.rules.count)
        XCTAssertEqual(original.defaultDecision, restored.defaultDecision)
    }
    
    func testComplexConditionSchema() throws {
        let schema = ConditionSchema(
            type: "all",
            value: nil,
            conditions: [
                ConditionSchema(type: "scopeType", value: .string("file")),
                ConditionSchema(type: "confidenceAbove", value: .number(0.8)),
                ConditionSchema(type: "maxSteps", value: .integer(3))
            ]
        )
        
        let condition = try schema.toCondition()
        
        // Create a matching task
        var task = AgentTask(
            title: "Test",
            intent: .addBinding(property: "x", in: "File.swift"),
            scope: .file(path: "File.swift"),
            steps: [TaskStep(description: "1", allowedFiles: [], expectedDiffType: .addWrapper)]
        )
        task.confidenceFactors = ["test": 0.9]
        
        XCTAssertTrue(condition.matches(task))
    }
    
    func testNotConditionSchema() throws {
        let schema = ConditionSchema(
            type: "not",
            value: nil,
            conditions: [
                ConditionSchema(type: "intentCategory", value: .string("architecture"))
            ]
        )
        
        let condition = try schema.toCondition()
        
        let docTask = AgentTask(
            title: "Test",
            intent: .documentPublicAPI(in: "File.swift"),
            scope: .file(path: "File.swift")
        )
        
        XCTAssertTrue(condition.matches(docTask))
    }
    
    func testInvalidDecisionThrows() {
        let schema = PolicySchema(
            name: "Bad",
            rules: [],
            defaultDecision: "invalid"
        )
        
        XCTAssertThrowsError(try schema.toPolicy()) { error in
            guard case PolicySchemaError.invalidDecision = error else {
                XCTFail("Expected invalidDecision error")
                return
            }
        }
    }
    
    func testInvalidConditionTypeThrows() {
        let schema = ConditionSchema(type: "unknownType", value: .string("x"))
        
        XCTAssertThrowsError(try schema.toCondition()) { error in
            guard case PolicySchemaError.unknownConditionType = error else {
                XCTFail("Expected unknownConditionType error")
                return
            }
        }
    }
    
    func testResolveBuiltinPolicy() throws {
        let conservative = try ApprovalPolicy.resolve("conservative")
        XCTAssertEqual(conservative.name, "Conservative")
        
        let moderate = try ApprovalPolicy.resolve("MODERATE") // Case insensitive
        XCTAssertEqual(moderate.name, "Moderate")
    }
    
    func testJSONOutput() throws {
        let policy = ApprovalPolicy.strict
        let json = try policy.toJSON()
        let jsonString = String(data: json, encoding: .utf8)!
        
        XCTAssertTrue(jsonString.contains("\"name\" : \"Strict\""))
        XCTAssertTrue(jsonString.contains("\"defaultDecision\" : \"requireHuman\""))
    }
}
