import XCTest
@testable import ArchitectCore

final class ExecutionSandboxTests: XCTestCase {
    
    func testPathValidation() {
        let sandbox = ExecutionSandbox(
            allowedPaths: ["Sources/Views/ProfileView.swift"],
            maxLinesChanged: 50
        )
        
        XCTAssertTrue(sandbox.isPathAllowed("Sources/Views/ProfileView.swift"))
        XCTAssertFalse(sandbox.isPathAllowed("Sources/Models/User.swift"))
    }
    
    func testWildcardPathValidation() {
        let sandbox = ExecutionSandbox(
            allowedPaths: ["Sources/Views/**"],
            maxLinesChanged: 50
        )
        
        XCTAssertTrue(sandbox.isPathAllowed("Sources/Views/ProfileView.swift"))
        XCTAssertTrue(sandbox.isPathAllowed("Sources/Views/Components/Button.swift"))
        XCTAssertFalse(sandbox.isPathAllowed("Sources/Models/User.swift"))
    }
    
    func testDiffValidation() throws {
        let sandbox = ExecutionSandbox(
            allowedPaths: ["test.swift"],
            maxLinesChanged: 5
        )
        
        let smallDiff = """
        +line1
        +line2
        -line3
        """
        
        XCTAssertNoThrow(try sandbox.validate(diff: smallDiff))
        
        let largeDiff = """
        +line1
        +line2
        +line3
        +line4
        +line5
        +line6
        """
        
        XCTAssertThrowsError(try sandbox.validate(diff: largeDiff)) { error in
            guard case SandboxViolation.tooManyChanges(let count, let max) = error else {
                XCTFail("Expected tooManyChanges error")
                return
            }
            XCTAssertEqual(count, 6)
            XCTAssertEqual(max, 5)
        }
    }
    
    func testSandboxForStep() {
        let step = TaskStep(
            description: "Add property",
            allowedFiles: ["ProfileView.swift"],
            expectedDiffType: .addProperty
        )
        
        let sandbox = ExecutionSandbox.forStep(step, scope: .module(name: "Views"))
        
        XCTAssertTrue(sandbox.allowedPaths.contains("ProfileView.swift"))
        XCTAssertEqual(sandbox.maxLinesChanged, 50)
        XCTAssertTrue(sandbox.mustPassTests)
        XCTAssertFalse(sandbox.allowNewFiles)
    }
    
    func testNewFileAllowed() {
        let step = TaskStep(
            description: "Create new file",
            allowedFiles: ["NewView.swift"],
            expectedDiffType: .addFile
        )
        
        let sandbox = ExecutionSandbox.forStep(step, scope: .module(name: "Views"))
        
        XCTAssertTrue(sandbox.allowNewFiles)
    }
}
