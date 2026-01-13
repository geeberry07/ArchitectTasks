import XCTest
@testable import ArchitectAnalysis
@testable import ArchitectCore

final class StyleAnalyzerTests: XCTestCase {
    
    // MARK: - Line Length Tests
    
    func testDetectsLongLines() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(maxLineLength: 80))
        
        let code = """
        import Foundation
        
        let shortLine = "ok"
        let veryLongLineWithLotsOfTextThatExceedsTheMaximumLineLengthConfiguredForThisTest = "too long"
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let lineLengthFindings = findings.filter { $0.context["issue"] == "lineLength" }
        XCTAssertEqual(lineLengthFindings.count, 1)
        XCTAssertEqual(lineLengthFindings.first?.location.line, 4)
    }
    
    func testCleanCodePassesLineLengthCheck() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(maxLineLength: 120))
        
        let code = """
        import Foundation
        
        let shortLine = "ok"
        let mediumLine = "This is a medium length line that should pass"
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let lineLengthFindings = findings.filter { $0.context["issue"] == "lineLength" }
        XCTAssertTrue(lineLengthFindings.isEmpty)
    }
    
    // MARK: - Trailing Whitespace Tests
    
    func testDetectsTrailingWhitespace() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectTrailingWhitespace: true))
        
        let code = "let x = 1   \nlet y = 2\n"
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let trailingFindings = findings.filter { $0.context["issue"] == "trailingWhitespace" }
        XCTAssertEqual(trailingFindings.count, 1)
        XCTAssertEqual(trailingFindings.first?.location.line, 1)
    }
    
    func testIgnoresTrailingWhitespaceWhenDisabled() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectTrailingWhitespace: false))
        
        let code = "let x = 1   \nlet y = 2\n"
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let trailingFindings = findings.filter { $0.context["issue"] == "trailingWhitespace" }
        XCTAssertTrue(trailingFindings.isEmpty)
    }
    
    // MARK: - Multiple Blank Lines Tests
    
    func testDetectsMultipleBlankLines() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectMultipleBlankLines: true))
        
        let code = """
        import Foundation
        
        
        
        let x = 1
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let blankLineFindings = findings.filter { $0.context["issue"] == "multipleBlankLines" }
        XCTAssertFalse(blankLineFindings.isEmpty)
    }
    
    func testAllowsSingleBlankLines() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectMultipleBlankLines: true))
        
        let code = """
        import Foundation
        
        let x = 1
        
        let y = 2
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let blankLineFindings = findings.filter { $0.context["issue"] == "multipleBlankLines" }
        XCTAssertTrue(blankLineFindings.isEmpty)
    }
    
    // MARK: - Trailing Newline Tests
    
    func testDetectsMissingTrailingNewline() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectTrailingNewline: true))
        
        let code = "let x = 1"  // No trailing newline
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let newlineFindings = findings.filter { $0.context["issue"] == "missingTrailingNewline" }
        XCTAssertEqual(newlineFindings.count, 1)
    }
    
    func testAcceptsTrailingNewline() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectTrailingNewline: true))
        
        let code = "let x = 1\n"  // Has trailing newline
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let newlineFindings = findings.filter { $0.context["issue"] == "missingTrailingNewline" }
        XCTAssertTrue(newlineFindings.isEmpty)
    }
    
    // MARK: - Import Order Tests
    
    func testDetectsUnsortedImports() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectImportOrder: true))
        
        let code = """
        import UIKit
        import Foundation
        import SwiftUI
        
        struct MyView: View {
            var body: some View { Text("Hi") }
        }
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let importFindings = findings.filter { $0.context["issue"] == "importOrder" }
        XCTAssertFalse(importFindings.isEmpty)
    }
    
    func testAcceptsSortedImports() throws {
        let analyzer = StyleAnalyzer(config: StyleAnalyzer.Config(detectImportOrder: true))
        
        let code = """
        import Foundation
        import SwiftUI
        import UIKit
        
        struct MyView: View {
            var body: some View { Text("Hi") }
        }
        """
        
        let findings = try analyzer.analyze(fileAt: "Test.swift", content: code)
        
        let importFindings = findings.filter { $0.context["issue"] == "importOrder" }
        XCTAssertTrue(importFindings.isEmpty)
    }
    
    // MARK: - Config Tests
    
    func testStrictConfig() throws {
        let config = StyleAnalyzer.Config.strict
        XCTAssertEqual(config.maxLineLength, 100)
        XCTAssertTrue(config.detectTrailingWhitespace)
        XCTAssertTrue(config.detectImportOrder)
    }
    
    func testLenientConfig() throws {
        let config = StyleAnalyzer.Config.lenient
        XCTAssertEqual(config.maxLineLength, 150)
        XCTAssertFalse(config.detectTrailingWhitespace)
        XCTAssertFalse(config.detectImportOrder)
    }
}
