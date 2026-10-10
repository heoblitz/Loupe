import Foundation
import LoupeCore
import Testing

struct RuntimeTouchActionTests {
    private let screen = LoupeSize(width: 390, height: 844)

    @Test func tapCountIsBackwardCompatibleAndValidatedBeforeDispatch() throws {
        let data = Data(#"{"command":"tap","start":{"x":20,"y":20},"holdDuration":0,"screen":{"width":390,"height":844}}"#.utf8)
        let legacy = try JSONDecoder().decode(LoupeRuntimeTouchActionRequest.self, from: data)
        #expect(legacy.tapCount == nil)
        #expect(legacy.validationError() == nil)
        var request = legacy
        request.tapCount = 2
        #expect(request.validationError() == nil)
        request.holdDuration = 0.5
        #expect(request.validationError() != nil)
        request.holdDuration = 0
        for count in [0, 3, -1] {
            request.tapCount = count
            #expect(request.validationError() != nil)
        }
        request.tapCount = 2
        request.command = .drag
        request.end = request.start
        #expect(request.validationError() != nil)
    }

    @Test func rejectsStaleOrInvalidGeometryBeforeDispatch() {
        for point in [LoupePoint(x: .nan, y: 10), LoupePoint(x: -1, y: 10), LoupePoint(x: 390, y: 10)] {
            #expect(LoupeRuntimeTouchActionRequest(command: .tap, start: point, screen: screen).validationError() != nil)
        }
        #expect(LoupeRuntimeTouchActionRequest(command: .drag, start: LoupePoint(x: 20, y: 20), screen: screen).validationError() != nil)
    }

    @Test func validatesHoldAndMovementTogether() {
        let start = LoupePoint(x: 20, y: 20)
        for duration in [Double.nan, .infinity, -1, 11] {
            #expect(LoupeRuntimeTouchActionRequest(command: .tap, start: start, holdDuration: duration, screen: screen).validationError() != nil)
        }
        #expect(LoupeRuntimeTouchActionRequest(command: .tap, start: start, holdDuration: 0.7, screen: screen).validationError() == nil)
        #expect(LoupeRuntimeTouchActionRequest(command: .drag, start: start, end: LoupePoint(x: 150, y: 20), duration: 0.5, holdDuration: 0.7, screen: screen).validationError() == nil)
        #expect(LoupeRuntimeTouchActionRequest(command: .drag, start: start, end: start, duration: 5, holdDuration: 6, screen: screen).validationError() != nil)
    }
}
