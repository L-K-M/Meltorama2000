import XCTest
import MeltoramaCore
@testable import MeltoramaMac

final class ExportTests: XCTestCase {
    func testSpeedChangesCountAndPreservesClock() {
        var doc=ProjectDocument()
        doc.keyframes=[KeyframeRecord(revision:0),KeyframeRecord(revision:0)]
        let normal=ExportService.movieSpec(for:doc,options:ExportOptions(format:.mp4))
        let fast=ExportService.movieSpec(for:doc,options:ExportOptions(format:.mp4,speed:.quadruple))
        let slow=ExportService.movieSpec(for:doc,options:ExportOptions(format:.mp4,speed:.half))
        XCTAssertEqual(normal.frameRate,30);XCTAssertEqual(fast.frameRate,30);XCTAssertEqual(slow.frameRate,30)
        XCTAssertLessThan(fast.totalFrames,normal.totalFrames);XCTAssertGreaterThan(slow.totalFrames,normal.totalFrames)
    }
    func testBoingOvershootsFieldAndBoundsLevers() throws {
        var doc=ProjectDocument()
        doc.keyframes=[KeyframeRecord(revision:0,easing:.boing),KeyframeRecord(revision:0,globals:GlobalParams(bulge:1))]
        let tween=try ExportService.makeTween(document:doc,frame:26,totalFrames:37,fps:30)
        XCTAssertGreaterThan(tween.fraction,1)
        XCTAssertEqual(tween.globals.bulge,1)
    }
}
