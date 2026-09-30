import XCTest
@testable import MeltoramaCore

final class InputMathTests: XCTestCase {
    func testResamplingIsIndependentOfInputEventSpacing() {
        let once = StrokeResampler(radius:0.1,aspect:1.6)
        once.begin(u:0.1,v:0.3)
        let one = once.extend(u:0.9,v:0.3)
        let many = StrokeResampler(radius:0.1,aspect:1.6)
        many.begin(u:0.1,v:0.3)
        var chopped: [Stamp] = []
        for i in 1...8 { chopped += many.extend(u:0.1+Float(i)*0.1,v:0.3) }
        XCTAssertEqual(one.count,chopped.count)
        for (a,b) in zip(one,chopped) { XCTAssertEqual(a.cx,b.cx,accuracy:0.000001); XCTAssertEqual(a.dx,b.dx,accuracy:0.000001) }
        XCTAssertEqual(one.first!.cx,0.1025,accuracy:0.000001)
        XCTAssertEqual(one.map(\.dx).reduce(0,+),one.last!.cx-0.1,accuracy:0.000001)
    }

    func testSymmetryUsesAspectSpaceAndPreservesSwirlChirality() {
        let stamp = Stamp(cx:0.6,cy:0.5,dx:0.02,dy:0)
        let rotated = Symmetry.family(tool:.smear,stamp:stamp,aspect:2,sectors:4)
        XCTAssertEqual(rotated[1].cx,0.5,accuracy:0.000001)
        XCTAssertEqual(rotated[1].cy,0.7,accuracy:0.000001)
        XCTAssertEqual(rotated[1].dx,0,accuracy:0.000001)
        XCTAssertEqual(rotated[1].dy,0.04,accuracy:0.000001)
        let swirls = Symmetry.family(tool:.vortex,stamp:Stamp(cx:0.6,cy:0.5,dx:1),aspect:2,sectors:4,mirrored:true)
        XCTAssertEqual(swirls.map(\.dx),[1,-1,1,-1,1,-1,1,-1])
    }

    func testPumpedMeltScheduleAndWhipAreBounded() {
        XCTAssertEqual(PumpStamps.firstPumpTick(tool:.grow),2)
        XCTAssertEqual(PumpStamps.at(tool:.unwind,u:0.5,v:0.5,tick:1).dx,-1)
        let early = PumpStamps.at(tool:.melt,u:0.2,v:0.5,tick:1).dy
        let late = PumpStamps.at(tool:.melt,u:0.2,v:0.5,tick:100).dy
        XCTAssertGreaterThan(late,early)
        XCTAssertLessThanOrEqual(late,0.02)
        XCTAssertTrue(GooWhip.tail(u:0.5,v:0.5,velU:.infinity,velV:1,aspect:1).isEmpty)
        XCTAssertTrue(GooWhip.tail(u:0.5,v:0.5,velU:0.2,velV:0,aspect:1).isEmpty)
        XCTAssertLessThanOrEqual(GooWhip.tail(u:0.5,v:0.5,velU:100,velV:0,aspect:2).count,64)
    }

    func testMovieSpeedChangesFrameCountAndPinsExactEnd() {
        let normal = MovieSpec(keyframeCount:3), double = MovieSpec(keyframeCount:3,speed:.double)
        XCTAssertEqual(normal.totalFrames,73)
        XCTAssertEqual(double.totalFrames,37)
        XCTAssertEqual(normal.frameRate,double.frameRate)
        XCTAssertEqual(double.timelinePosition(frame:double.totalFrames-1),2)
        XCTAssertEqual(MovieSpec.gifFPS(keyframeCount:64,speed:.half),2)
        XCTAssertEqual(MovieSpec.videoSize(width:4033,height:3025).0 % 2,0)
    }

    func testEasingAndLensTweenAndWobbleKeepDocumentMeaning() {
        for easing in Easing.allCases { XCTAssertEqual(easing.at(0),0); XCTAssertEqual(easing.at(1),1) }
        XCTAssertGreaterThan(tweenProgress(0.6,easing:.boing),1)
        XCTAssertEqual(leverProgress(0.6,easing:.boing),1)
        let a = GlobalParams(lenses:[Lens(u:0.2,v:0.5,strength:0.8)])
        let b = GlobalParams(lenses:[Lens(u:0.8,v:0.5,type:.vortex,strength:0.4)])
        XCTAssertEqual(a.lerp(b,t:0.5).lenses[0].u,0.5,accuracy:0.000001)
        XCTAssertEqual(a.lerp(b,t:0.5).lenses[0].type,.vortex)
        let wobble = GlobalWobble(levers:[LeverWobble(rate:8,depth:1)])
        XCTAssertEqual(wobble.cappedFor(loopSeconds:0.3).levers[0].rate,0)
        XCTAssertEqual(leversAt(base:a,wobble:wobble,phase:0.1).lenses,a.lenses)
    }

    func testGooMeRecipesAreDeterministicAndUseful() {
        let a = GooMe.makeDeal(seed:1234,aspect:1.5)
        let b = GooMe.makeDeal(seed:1234,aspect:1.5)
        XCTAssertEqual(a.strokes,b.strokes)
        XCTAssertEqual(a.globals,b.globals)
        XCTAssertEqual(a.globals,DealLevers.draw(seed:1234))
        // These numbers were emitted by Android's compiled GooMe class.
        XCTAssertEqual(a.strokes.map(\.tool),[.vortex,.grow])
        XCTAssertEqual(a.strokes[0].stamps[0].cx,0.38084936,accuracy:0.0000001)
        XCTAssertEqual(a.strokes[0].stamps[0].cy,0.5375791,accuracy:0.0000001)
        XCTAssertFalse(a.strokes.isEmpty)
        XCTAssertTrue(a.strokes.allSatisfy(\.isValid))
        let signatures = Set((0..<40).map { GooMe.deal(seed:UInt64($0),aspect:1).map { $0.tool.rawValue }.joined(separator:",") })
        XCTAssertGreaterThan(signatures.count,5)
    }

    func testPinPullAndPortalsUseRoundDistances() {
        XCTAssertNil(PinPull.warpFor(holds:[],puck:MlsControl(su:0.5,sv:0.5,tu:0.501,tv:0.5)))
        let warp = PinPull.warpFor(holds:[(0.2,0.3)],puck:MlsControl(su:0.5,sv:0.5,tu:0.6,tv:0.5))!
        XCTAssertEqual(warp.controls.count,6)
        XCTAssertTrue(warp.isValid)
        let pair = PortalPair(au:0.2,av:0.5,bu:0.8,bv:0.5)
        XCTAssertNil(Portals.shiftAt(u:0.3,v:0.5,radius:0.15,aspect:2,pair:pair))
        XCTAssertEqual(Portals.shiftAt(u:0.2,v:0.5,radius:0.15,aspect:2,pair:pair)!.0,0.6,accuracy:0.000001)
    }
}
