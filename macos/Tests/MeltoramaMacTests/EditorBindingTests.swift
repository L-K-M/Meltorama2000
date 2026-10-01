import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class EditorBindingTests: XCTestCase {
    func testRetainedKeyframeBindingSurvivesDeleteAndCrop() {
        let session = EditorSession()
        session.state.keyframes = [KeyframeRecord(revision: 0, easing: .boing)]
        session.selectedKeyframe = 0
        let binding = EditorBindings.keyframeEasing(session: session, index: 0)
        XCTAssertEqual(binding.wrappedValue, .boing)
        session.state.keyframes = []
        XCTAssertEqual(binding.wrappedValue, .linear)
        binding.wrappedValue = .ease
        XCTAssertTrue(session.state.keyframes.isEmpty)
    }

    func testRetainedLensBindingsSurviveRemoveAndDocumentRestore() {
        let session = EditorSession()
        session.state.globals.lenses = [Lens(type: .vortex, strength: 0.7)]
        session.selectedLens = 0
        let type = EditorBindings.lens(session: session, index: 0, keyPath: \.type,
                                       fallback: LensType.bulge, name: "Change Lens")
        let radius = EditorBindings.lens(session: session, index: 0, keyPath: \.radius,
                                         fallback: Float(0.18), name: "Resize Lens")
        let strength = EditorBindings.lens(session: session, index: 0, keyPath: \.strength,
                                           fallback: Float(0), name: "Adjust Lens")
        session.state.globals.lenses = []
        XCTAssertEqual(type.wrappedValue, .bulge)
        XCTAssertEqual(radius.wrappedValue, 0.18)
        XCTAssertEqual(strength.wrappedValue, 0)
        type.wrappedValue = .pinch
        radius.wrappedValue = 0.4
        strength.wrappedValue = 0.9
        XCTAssertTrue(session.state.globals.lenses.isEmpty)
    }

    func testOldBindingsCannotChangeAReplacementSelection() {
        let session = EditorSession()
        session.state.keyframes = [KeyframeRecord(revision: 0, easing: .boing)]
        session.state.globals.lenses = [Lens(type: .vortex)]
        session.selectedKeyframe = 0
        session.selectedLens = 0
        let easing = EditorBindings.keyframeEasing(session: session, index: 0)
        let type = EditorBindings.lens(session: session, index: 0, keyPath: \.type,
                                       fallback: LensType.bulge, name: "Change Lens")
        session.selectedKeyframe = nil
        session.selectedLens = nil
        easing.wrappedValue = .ease
        type.wrappedValue = .pinch
        XCTAssertEqual(session.state.keyframes[0].easing, .boing)
        XCTAssertEqual(session.state.globals.lenses[0].type, .vortex)
    }
}
