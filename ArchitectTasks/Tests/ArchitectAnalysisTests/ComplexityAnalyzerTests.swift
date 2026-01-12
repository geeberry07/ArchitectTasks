import XCTest
@testable import ArchitectCore
@testable import ArchitectAnalysis

final class ComplexityAnalyzerTests: XCTestCase {
    
    func testDetectsLongFunction() throws {
        let source = """
        func longFunction() {
            let a = 1
            let b = 2
            let c = 3
            let d = 4
            let e = 5
            let f = 6
            let g = 7
            let h = 8
            let i = 9
            let j = 10
            let k = 11
            let l = 12
        }
        """
        
        let analyzer = ComplexityAnalyzer(thresholds: .init(maxFunctionLines: 10))
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.context["metric"] == "functionLines" })
    }
    
    func testDetectsTooManyParameters() throws {
        let source = """
        func manyParams(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {
            print(a + b + c + d + e + f)
        }
        """
        
        let analyzer = ComplexityAnalyzer(thresholds: .init(maxFunctionParameters: 4))
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertFalse(findings.isEmpty)
        let paramFinding = findings.first { $0.context["metric"] == "parameterCount" }
        XCTAssertNotNil(paramFinding)
        XCTAssertEqual(paramFinding?.context["value"], "6")
    }
    
    func testDetectsDeepNesting() throws {
        let source = """
        func nested() {
            if true {
                if true {
                    if true {
                        if true {
                            if true {
                                print("deep")
                            }
                        }
                    }
                }
            }
        }
        """
        
        let analyzer = ComplexityAnalyzer(thresholds: .init(maxNestingDepth: 3))
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.context["metric"] == "nestingDepth" })
    }
    
    func testDetectsHighCyclomaticComplexity() throws {
        let source = """
        func complex(a: Int, b: Bool, c: Bool) -> Int {
            if a > 0 {
                if b {
                    return 1
                } else if c {
                    return 2
                } else {
                    return 3
                }
            } else if a < 0 {
                switch a {
                case -1: return 4
                case -2: return 5
                default: return 6
                }
            } else {
                return b && c ? 7 : 8
            }
        }
        """
        
        let analyzer = ComplexityAnalyzer(thresholds: .init(maxCyclomaticComplexity: 5))
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.context["metric"] == "cyclomaticComplexity" })
    }
    
    func testDetectsLargeFile() throws {
        let lines = (1...100).map { "let x\($0) = \($0)" }
        let source = lines.joined(separator: "\n")
        
        let analyzer = ComplexityAnalyzer(thresholds: .init(maxFileLines: 50))
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertFalse(findings.isEmpty)
        let fileFinding = findings.first { $0.context["metric"] == "fileLines" }
        XCTAssertNotNil(fileFinding)
    }
    
    func testCleanCodePassesAnalysis() throws {
        let source = """
        func simple(value: Int) -> Int {
            return value * 2
        }
        
        func another() {
            print("hello")
        }
        """
        
        let analyzer = ComplexityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertTrue(findings.isEmpty)
    }
    
    func testStrictThresholds() throws {
        let source = """
        func mediumFunction(a: Int, b: Int, c: Int, d: Int) {
            if a > 0 {
                if b > 0 {
                    if c > 0 {
                        print("nested")
                    }
                }
            }
        }
        """
        
        // Default thresholds should pass
        let defaultAnalyzer = ComplexityAnalyzer()
        let defaultFindings = try defaultAnalyzer.analyze(fileAt: "Test.swift", content: source)
        
        // Strict thresholds should fail
        let strictAnalyzer = ComplexityAnalyzer(thresholds: .strict)
        let strictFindings = try strictAnalyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertTrue(strictFindings.count > defaultFindings.count)
    }
}
