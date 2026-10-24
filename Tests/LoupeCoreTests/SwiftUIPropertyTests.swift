import Foundation
import LoupeCore
import Testing

struct SwiftUIPropertyTests {
    @Test func olderPropertiesDecodeWithoutAnUnavailableReason() throws {
        let data = Data(#"{"name":"mode","typeName":"String","value":{"type":"string","value":"Inspect"},"evidence":[]}"#.utf8)
        let property = try JSONDecoder().decode(LoupeSwiftUIProperty.self, from: data)
        #expect(property.value == .string("Inspect"))
        #expect(property.valueUnavailableReason == nil)
    }

    @Test func unavailableStatePreservesItsReasonInSnapshots() throws {
        let property = LoupeSwiftUIProperty(
            name: "mode", typeName: "SwiftUI.LazyState<String>",
            valueUnavailableReason: "deferredInitializer", evidence: ["privateReflection"]
        )
        let data = try JSONEncoder().encode(property)
        let decoded = try JSONDecoder().decode(LoupeSwiftUIProperty.self, from: data)
        #expect(decoded == property)
        #expect(decoded.value == nil)
        #expect(decoded.valueUnavailableReason == "deferredInitializer")
    }
}
