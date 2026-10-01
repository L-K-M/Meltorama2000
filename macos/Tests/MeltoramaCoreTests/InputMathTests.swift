import XCTest
@testable import MeltoramaCore

final class InputMathTests: XCTestCase {
    func testLargeResamplingSegmentHasBoundedWorkAndPreservesMovement() throws {
        let sampler = StrokeResampler(radius: 0.01, aspect: 1)
        sampler.begin(u: 0.5, v: 0.5)
        // About 8,000 nominal stamps: safely exposes the missing work cap
        // without entering the Float plateau or allocating millions of stamps.
        let stamps = sampler.extend(u: 0.5, v: 20.5)
        XCTAssertLessThanOrEqual(stamps.count, 4096)
        XCTAssertEqual(try XCTUnwrap(stamps.first).cy, 0.5025, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(stamps.last).cy, 20.5)
        XCTAssertEqual(stamps.map(\.dy).reduce(0, +), 20, accuracy: 0.00001)
        XCTAssertTrue(stamps.allSatisfy { [$0.cx, $0.cy, $0.dx, $0.dy].allSatisfy(\.isFinite) })
        let continuation = sampler.extend(u: 0.5, v: 20.51)
        XCTAssertEqual(try XCTUnwrap(continuation.first).dy, 0.0025, accuracy: 0.000002)
    }

    func testFloatPlateauAndOverflowSegmentsRemainFiniteAndBounded() throws {
        let sampler = StrokeResampler(radius: 0.01, aspect: 65535)
        sampler.begin(u: 0.5, v: 0.5)
        // A 100-point drag on a native 65535 × 1 image at 10% Fit.
        // The old accumulator reaches 65536, where adding .0025 stalls.
        let endpoint: Float = 76919.516
        let stamps = sampler.extend(u: 0.5, v: endpoint)
        XCTAssertEqual(stamps.count, StrokeResampler.maxStampsPerSegment)
        XCTAssertEqual(try XCTUnwrap(stamps.first).cy, 0.5025, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(stamps.last).cy, endpoint)
        XCTAssertEqual(stamps.reduce(Double(0)) { $0 + Double($1.dy) }, Double(endpoint)-0.5, accuracy: 0.002)
        XCTAssertTrue(stamps.allSatisfy { [$0.cx, $0.cy, $0.dx, $0.dy].allSatisfy(\.isFinite) })

        let overflow = StrokeResampler(radius: 0.01, aspect: 2)
        overflow.begin(u: -.greatestFiniteMagnitude, v: 0)
        let extremes = overflow.extend(u: .greatestFiniteMagnitude, v: 0)
        XCTAssertEqual(extremes.count, StrokeResampler.maxStampsPerSegment)
        XCTAssertEqual(try XCTUnwrap(extremes.last).cx, .greatestFiniteMagnitude)
        XCTAssertTrue(extremes.allSatisfy { [$0.cx, $0.cy, $0.dx, $0.dy].allSatisfy(\.isFinite) })

        let underflow = StrokeResampler(radius: .leastNonzeroMagnitude, aspect: 1)
        underflow.begin(u: 0, v: 0)
        XCTAssertEqual(underflow.extend(u: 1, v: 0).count, StrokeResampler.maxStampsPerSegment)
    }

    func testCoarsenedSegmentKeepsUnstampedMovementAcrossCorner() throws {
        let sampler = StrokeResampler(radius: 0.1, aspect: 1)
        sampler.begin(u: 0.1, v: 0.3)
        XCTAssertTrue(sampler.extend(u: 0.102, v: 0.3).isEmpty)
        let stamps = sampler.extend(u: 0.102, v: 200.3)
        let first = try XCTUnwrap(stamps.first)
        XCTAssertEqual(first.cx, 0.102)
        XCTAssertEqual(first.cy, 0.302, accuracy: 0.000001)
        XCTAssertEqual(first.dx, 0.002, accuracy: 0.000001)
        XCTAssertEqual(stamps.reduce(Double(0)) { $0 + Double($1.dx) }, 0.002, accuracy: 0.000001)
        XCTAssertEqual(stamps.reduce(Double(0)) { $0 + Double($1.dy) }, 200, accuracy: 0.00001)
    }

    func testInvalidInputDoesNotPoisonValidResampling() {
        let sampler = StrokeResampler(radius: 0.1, aspect: 1)
        sampler.begin(u: .nan, v: 0)
        XCTAssertTrue(sampler.extend(u: 0.5, v: 0.5).isEmpty)
        sampler.begin(u: 0.1, v: 0.3)
        sampler.begin(u: 0.9, v: .infinity)
        XCTAssertTrue(sampler.extend(u: .infinity, v: 0.3).isEmpty)
        let actual = sampler.extend(u: 0.3, v: 0.3)
        let expected = StrokeResampler(radius: 0.1, aspect: 1)
        expected.begin(u: 0.1, v: 0.3)
        XCTAssertEqual(actual, expected.extend(u: 0.3, v: 0.3))
    }

    func testNoiseSaturatesOutOfRangeCoordinatesWithoutTrappingOrExtrapolating() {
        // Ordinary reference values from the original Android-matching port.
        XCTAssertEqual(ValueNoise.at(x: 0, y: 0, seed: 4), 0.7125572)
        XCTAssertEqual(ValueNoise.at(x: 3.125, y: -2.75, seed: 4), 0.30084378)
        XCTAssertEqual(ValueNoise.at(x: -0.2, y: 0.25, seed: 1), 0.63786006)
        XCTAssertEqual(ValueNoise.at(x: 2_419_781_632, y: 0, seed: 4),
                       ValueNoise.hash(x: UInt32(bitPattern: Int32.max), y: 0, seed: 4))
        XCTAssertEqual(ValueNoise.at(x: -.greatestFiniteMagnitude, y: 0, seed: 4),
                       ValueNoise.hash(x: UInt32(bitPattern: Int32.min), y: 0, seed: 4))
        for coordinate: Float in [.greatestFiniteMagnitude, Float(Int32.max), Float(Int32.min)] {
            let sample = ValueNoise.at(x: coordinate, y: -coordinate, seed: 4)
            XCTAssertTrue(sample.isFinite)
            XCTAssertTrue((0...1).contains(sample))
        }
        XCTAssertEqual(ValueNoise.at(x: .nan, y: 0, seed: 4), 0)
        XCTAssertEqual(ValueNoise.at(x: 0, y: .infinity, seed: 4), 0)
        let melt = PumpStamps.at(tool: .melt, u: 60_494_544, v: 0.5, tick: 100)
        XCTAssertTrue(melt.dy.isFinite)
        XCTAssertTrue((0.007...0.02).contains(melt.dy))
    }

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
