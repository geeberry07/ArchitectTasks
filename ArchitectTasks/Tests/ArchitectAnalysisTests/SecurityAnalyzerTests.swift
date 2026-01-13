import XCTest
@testable import ArchitectAnalysis
@testable import ArchitectCore

final class SecurityAnalyzerTests: XCTestCase {
    
    func testDetectsForceUnwrap() throws {
        let source = """
        func process(value: String?) {
            let unwrapped = value!
            print(unwrapped)
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].type, .securityIssue)
        XCTAssertEqual(findings[0].context["issue"], "forceUnwrap")
    }
    
    func testDetectsForceTry() throws {
        let source = """
        func loadData() {
            let data = try! Data(contentsOf: URL(string: "https://example.com")!)
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        let forceTryFindings = findings.filter { $0.context["issue"] == "forceTry" }
        XCTAssertEqual(forceTryFindings.count, 1)
    }
    
    func testDetectsImplicitlyUnwrappedOptional() throws {
        let source = """
        class ViewController {
            var label: UILabel!
            var button: UIButton!
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        let implicitUnwrapFindings = findings.filter { $0.context["issue"] == "implicitUnwrap" }
        XCTAssertEqual(implicitUnwrapFindings.count, 2)
    }
    
    func testDetectsHardcodedSecret() throws {
        let source = """
        struct Config {
            let apiKey = "sk-1234567890abcdef"
            let password = "supersecret123"
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        let secretFindings = findings.filter { $0.context["issue"] == "hardcodedSecret" }
        XCTAssertEqual(secretFindings.count, 2)
        XCTAssertEqual(secretFindings[0].severity, .error)
    }
    
    func testDetectsUnsafeAPI() throws {
        let source = """
        func dangerous() {
            let ptr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
            ptr.deallocate()
            
            let value = unsafeBitCast(ptr, to: Int.self)
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        let unsafeFindings = findings.filter { $0.context["issue"] == "unsafeAPI" }
        XCTAssertGreaterThanOrEqual(unsafeFindings.count, 1)
    }
    
    func testCleanCodePassesAnalysis() throws {
        let source = """
        func safeProcess(value: String?) {
            guard let unwrapped = value else { return }
            print(unwrapped)
        }
        
        func safeLoad() throws {
            let data = try Data(contentsOf: URL(string: "https://example.com")!)
        }
        """
        
        let analyzer = SecurityAnalyzer()
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        // Should only find the force unwrap in the URL, not force try
        let forceTryFindings = findings.filter { $0.context["issue"] == "forceTry" }
        XCTAssertEqual(forceTryFindings.count, 0)
    }
    
    func testConfigurableDetection() throws {
        let source = """
        func process(value: String?) {
            let unwrapped = value!
        }
        """
        
        // Disable force unwrap detection
        let config = SecurityAnalyzer.Config(detectForceUnwrap: false)
        let analyzer = SecurityAnalyzer(config: config)
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: source)
        
        let forceUnwrapFindings = findings.filter { $0.context["issue"] == "forceUnwrap" }
        XCTAssertEqual(forceUnwrapFindings.count, 0)
    }
}
