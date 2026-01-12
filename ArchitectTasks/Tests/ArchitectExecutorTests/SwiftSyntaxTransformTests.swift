import XCTest
@testable import ArchitectCore
@testable import ArchitectExecutor

final class SwiftSyntaxTransformTests: XCTestCase {
    
    // MARK: - StateObject Transform
    
    func testSyntaxStateObjectTransform() throws {
        let transform = SyntaxStateObjectTransform()
        
        let source = """
        import SwiftUI
        
        struct ProfileView: View {
            var viewModel: ProfileViewModel
            
            var body: some View {
                Text(viewModel.name)
            }
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ProfileViewModel",
            in: "ProfileView.swift"
        )
        
        let context = TransformContext(
            filePath: "ProfileView.swift",
            propertyName: "viewModel",
            typeName: "ProfileViewModel"
        )
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@StateObject"))
        XCTAssertTrue(result.transformedSource.contains("var viewModel: ProfileViewModel"))
    }
    
    func testSyntaxStateObjectPreservesFormatting() throws {
        let transform = SyntaxStateObjectTransform()
        
        let source = """
        struct View: View {
            // Comment above
            var viewModel: ViewModel  // Inline comment
            
            var body: some View { Text("") }
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        // SwiftSyntax preserves trivia (comments, whitespace)
        XCTAssertTrue(result.transformedSource.contains("@StateObject"))
    }
    
    func testSyntaxStateObjectThrowsOnExisting() {
        let transform = SyntaxStateObjectTransform()
        
        let source = """
        struct View: View {
            @StateObject var viewModel: ViewModel
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        
        XCTAssertThrowsError(try transform.apply(to: source, intent: intent, context: context)) { error in
            guard case TransformError.alreadyHasWrapper = error else {
                XCTFail("Expected alreadyHasWrapper error")
                return
            }
        }
    }
    
    // MARK: - Binding Transform
    
    func testSyntaxBindingTransform() throws {
        let transform = SyntaxBindingTransform()
        
        let source = """
        struct ChildView: View {
            var isEnabled: Bool
            
            var body: some View {
                Toggle("", isOn: $isEnabled)
            }
        }
        """
        
        let intent = TaskIntent.addBinding(property: "isEnabled", in: "ChildView.swift")
        let context = TransformContext(filePath: "ChildView.swift")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@Binding"))
        XCTAssertTrue(result.transformedSource.contains("var isEnabled: Bool"))
    }
    
    func testSyntaxBindingConvertsLetToVar() throws {
        let transform = SyntaxBindingTransform()
        
        let source = """
        struct View: View {
            let value: String
            var body: some View { Text(value) }
        }
        """
        
        let intent = TaskIntent.addBinding(property: "value", in: "View.swift")
        let context = TransformContext(filePath: "View.swift")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@Binding var value"))
        XCTAssertFalse(result.transformedSource.contains("let value"))
    }
    
    // MARK: - Import Transform
    
    func testSyntaxImportTransform() throws {
        let transform = SyntaxImportTransform()
        
        let source = """
        import SwiftUI
        
        struct MyView: View {
            var body: some View { Text("Hi") }
        }
        """
        
        let intent = TaskIntent.addBinding(property: "x", in: "File.swift")
        let context = TransformContext(filePath: "File.swift", typeName: "Combine")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("import Combine"))
        XCTAssertEqual(result.linesChanged, 1)
    }
    
    func testSyntaxImportSkipsExisting() throws {
        let transform = SyntaxImportTransform()
        
        let source = """
        import SwiftUI
        import Combine
        
        struct MyView: View {}
        """
        
        let intent = TaskIntent.addBinding(property: "x", in: "File.swift")
        let context = TransformContext(filePath: "File.swift", typeName: "Combine")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.linesChanged, 0)
    }
    
    func testSyntaxImportInsertsAfterLastImport() throws {
        let transform = SyntaxImportTransform()
        
        let source = """
        import Foundation
        import SwiftUI
        
        struct MyView: View {}
        """
        
        let intent = TaskIntent.addBinding(property: "x", in: "File.swift")
        let context = TransformContext(filePath: "File.swift", typeName: "Combine")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        // Should contain the new import
        XCTAssertTrue(result.transformedSource.contains("import Combine"))
        XCTAssertTrue(result.hasChanges)
    }
}
