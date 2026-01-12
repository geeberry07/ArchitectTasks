import XCTest
@testable import ArchitectCore
@testable import ArchitectExecutor

final class BindingTransformTests: XCTestCase {
    
    let transform = BindingTransform()
    
    func testAddBindingToProperty() throws {
        let source = """
        import SwiftUI
        
        struct ChildView: View {
            var isEnabled: Bool
            
            var body: some View {
                Toggle("Enabled", isOn: $isEnabled)
            }
        }
        """
        
        let intent = TaskIntent.addBinding(property: "isEnabled", in: "ChildView.swift")
        let context = TransformContext(filePath: "ChildView.swift", propertyName: "isEnabled")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@Binding var isEnabled: Bool"))
        XCTAssertEqual(result.linesChanged, 1)
    }
    
    func testThrowsWhenAlreadyHasBinding() {
        let source = """
        struct View: View {
            @Binding var value: String
        }
        """
        
        let intent = TaskIntent.addBinding(property: "value", in: "View.swift")
        let context = TransformContext(filePath: "View.swift")
        
        XCTAssertThrowsError(try transform.apply(to: source, intent: intent, context: context)) { error in
            guard case TransformError.alreadyHasWrapper = error else {
                XCTFail("Expected alreadyHasWrapper error")
                return
            }
        }
    }
    
    func testThrowsWhenPropertyNotFound() {
        let source = """
        struct View: View {
            var other: Int
        }
        """
        
        let intent = TaskIntent.addBinding(property: "value", in: "View.swift")
        let context = TransformContext(filePath: "View.swift")
        
        XCTAssertThrowsError(try transform.apply(to: source, intent: intent, context: context)) { error in
            guard case TransformError.propertyNotFound = error else {
                XCTFail("Expected propertyNotFound error")
                return
            }
        }
    }
    
    func testPreservesIndentation() throws {
        let source = """
        struct View: View {
                var value: String
        }
        """
        
        let intent = TaskIntent.addBinding(property: "value", in: "View.swift")
        let context = TransformContext(filePath: "View.swift")
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.transformedSource.contains("        @Binding var value"))
    }
    
    func testImportTransform() throws {
        let importTransform = ImportTransform()
        
        let source = """
        import SwiftUI
        
        struct MyView: View {
            var body: some View { Text("Hi") }
        }
        """
        
        let intent = TaskIntent.addBinding(property: "x", in: "File.swift") // Intent doesn't matter for import
        let context = TransformContext(filePath: "File.swift", typeName: "Combine")
        
        let result = try importTransform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.transformedSource.contains("import Combine"))
        XCTAssertEqual(result.linesChanged, 1)
    }
    
    func testImportTransformSkipsExisting() throws {
        let importTransform = ImportTransform()
        
        let source = """
        import SwiftUI
        import Combine
        
        struct MyView: View {}
        """
        
        let intent = TaskIntent.addBinding(property: "x", in: "File.swift")
        let context = TransformContext(filePath: "File.swift", typeName: "Combine")
        
        let result = try importTransform.apply(to: source, intent: intent, context: context)
        
        XCTAssertFalse(result.hasChanges)
        XCTAssertEqual(result.linesChanged, 0)
        XCTAssertFalse(result.warnings.isEmpty)
    }
    
    func testTransformRegistryBuiltins() {
        let registry = TransformRegistry.shared
        registry.registerBuiltins()
        
        XCTAssertNotNil(registry.transform(for: .addStateObject(property: "x", type: "Y", in: "Z")))
        XCTAssertNotNil(registry.transform(for: .addBinding(property: "x", in: "Y")))
    }
}
