import Foundation
import Testing
import LoupeCore
@testable import LoupeCLI

struct WebAccessibilityTests {
    @Test func targetedSearchUsesOnePointOnlyInsideVisibleWebView() {
        let visible = [LoupeRect(x: 20, y: 40, width: 200, height: 100)]
        let point = LoupePoint(x: 80, y: 60)
        #expect(webSearchRegions(visible, near: nil) == visible)
        #expect(webSearchRegions(visible, near: point) == [LoupeRect(x: 67.5, y: 47.5, width: 25, height: 25)])
        #expect(webSearchRegions(visible, near: LoupePoint(x: 220, y: 60)).isEmpty)
    }

    @Test func decodesTranslatorRoleAndReportsSampling() throws {
        let data = Data(#"[{"id":"1:2","role":15,"enabled":true,"focused":true,"frame":{"x":10,"y":20,"width":100,"height":30},"point":{"x":60,"y":35},"label":"Name","value":"Loupe"}]"#.utf8)
        let element = try #require(JSONDecoder().decode([WebAccessibilityElement].self, from: data).first)
        #expect(element.roleName == "textField")
        #expect(element.supportsTap)
        #expect(element.focused)
        let result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WebAccessibilityResult(elements: [element]))) as? [String: Any]
        #expect(result?["complete"] as? Bool == false)
        let elements = try #require(result?["elements"] as? [[String: Any]])
        #expect(elements.first?["role"] as? String == "textField")
    }
}
