import Foundation

public enum Symmetry {
    public static let maxSectors = 12
    public static func family(tool: BrushTool, stamp: Stamp, aspect: Float, sectors: Int = 1, mirrored: Bool = false) -> [Stamp] {
        let sectors = max(1,min(maxSectors,sectors))
        let ax = (stamp.cx-0.5)*aspect, ay = stamp.cy-0.5
        let adx = stamp.dx*aspect, ady = stamp.dy
        var output: [Stamp] = []
        for j in 0..<sectors {
            let copy: Stamp
            if j == 0 { copy = stamp }
            else {
                let theta = 2 * Float.pi * Float(j)/Float(sectors), c = cos(theta), s = sin(theta)
                copy = Stamp(cx: 0.5+(ax*c-ay*s)/aspect,cy: 0.5+ax*s+ay*c,
                             dx: tool.mode.rotatesDelta ? (adx*c-ady*s)/aspect : stamp.dx,
                             dy: tool.mode.rotatesDelta ? adx*s+ady*c : stamp.dy)
            }
            output.append(copy)
            if mirrored { output.append(tool.mirrorStamp(copy)) }
        }
        return output
    }
}

public final class StrokeResampler {
    public static let maxStampsPerSegment = 4096
    private let aspect: Float
    private let firstTravel: Float
    private let spacing: Float
    private var lastU: Float = 0, lastV: Float = 0, stampU: Float = 0, stampV: Float = 0
    private var toNext: Float = 0
    private var started = false
    public init(radius: Float, aspect: Float, spacingFraction: Float = 0.25, firstTravel: Float = 0.004, maxSpacing: Float = .greatestFiniteMagnitude) {
        precondition(radius.isFinite && radius > 0 && aspect.isFinite && aspect > 0)
        precondition(spacingFraction.isFinite && spacingFraction > 0 && firstTravel.isFinite && firstTravel > 0 && maxSpacing.isFinite && maxSpacing > 0)
        self.aspect = aspect; self.firstTravel = firstTravel
        spacing = max(.leastNormalMagnitude,min(spacingFraction*radius,max(maxSpacing,0.002)))
    }
    public func begin(u: Float, v: Float) {
        guard u.isFinite, v.isFinite else { return }
        lastU = u; lastV = v; stampU = u; stampV = v; started = true
        toNext = min(spacing,firstTravel)
    }
    public func extend(u: Float, v: Float) -> [Stamp] {
        guard started, [u,v,lastU,lastV,stampU,stampV].allSatisfy(\.isFinite) else { return [] }
        // A narrow source or a drag outside the photo can span millions of
        // nominal intervals. Double preflight avoids Float overflow before
        // choosing a bounded path; ordinary strokes retain Android's math.
        let preciseDU = Double(u)-Double(lastU), preciseDV = Double(v)-Double(lastV)
        let preciseSegment = hypot(preciseDU*Double(aspect),preciseDV)
        guard preciseSegment.isFinite, preciseSegment > 0 else { return [] }
        let budgetDistance = Double(toNext)+Double(spacing)*Double(Self.maxStampsPerSegment-1)
        if preciseSegment > budgetDistance {
            return coarsenedSegment(u:u,v:v,du:preciseDU,dv:preciseDV,length:preciseSegment)
        }
        let du = u-lastU, dv = v-lastV, segment = hypot(du*aspect,dv)
        guard du.isFinite, dv.isFinite, segment.isFinite, segment > 0 else {
            return coarsenedSegment(u:u,v:v,du:preciseDU,dv:preciseDV,length:preciseSegment)
        }
        var traveled: Float = 0
        var remaining = toNext, previousU = stampU, previousV = stampV
        var result: [Stamp] = []
        while result.count < Self.maxStampsPerSegment, traveled+remaining <= segment {
            let next = traveled+remaining
            guard next.isFinite, next > traveled else {
                return coarsenedSegment(u:u,v:v,du:preciseDU,dv:preciseDV,length:preciseSegment)
            }
            traveled = next
            let t = traveled/segment, cx = lastU+du*t, cy = lastV+dv*t
            let stamp = Stamp(cx:cx,cy:cy,dx:cx-previousU,dy:cy-previousV)
            guard [stamp.cx,stamp.cy,stamp.dx,stamp.dy].allSatisfy(\.isFinite) else {
                return coarsenedSegment(u:u,v:v,du:preciseDU,dv:preciseDV,length:preciseSegment)
            }
            result.append(stamp)
            previousU = cx; previousV = cy; remaining = spacing
        }
        // Rounding near the budget must not turn the nominal walk into an
        // unbounded loop either. State is still untouched if we resample it.
        if traveled+remaining <= segment {
            return coarsenedSegment(u:u,v:v,du:preciseDU,dv:preciseDV,length:preciseSegment)
        }
        toNext = remaining-(segment-traveled)
        stampU = previousU; stampV = previousV; lastU = u; lastV = v
        return result
    }
    private func coarsenedSegment(u: Float,v: Float,du: Double,dv: Double,length: Double) -> [Stamp] {
        // Keep the first responsive stamp, then spread the remaining budget
        // across the whole path. Ending exactly at the pointer preserves the
        // total displacement and gives the next segment a clean spacing gate.
        let first = min(Double(toNext),length)
        var previousU = stampU, previousV = stampV
        var result: [Stamp] = []
        result.reserveCapacity(Self.maxStampsPerSegment)
        for i in 0..<Self.maxStampsPerSegment {
            let fraction = (first+(length-first)*Double(i)/Double(Self.maxStampsPerSegment-1))/length
            let cx = i == Self.maxStampsPerSegment-1 ? u : Float(Double(lastU)+du*fraction)
            let cy = i == Self.maxStampsPerSegment-1 ? v : Float(Double(lastV)+dv*fraction)
            let stamp = Stamp(cx:cx,cy:cy,dx:cx-previousU,dy:cy-previousV)
            guard [stamp.cx,stamp.cy,stamp.dx,stamp.dy].allSatisfy(\.isFinite) else { return [] }
            result.append(stamp)
            previousU = cx; previousV = cy
        }
        stampU = u; stampV = v; lastU = u; lastV = v; toNext = spacing
        return result
    }
    public static func firstTravelFor(imageHeight: Float) -> Float {
        guard imageHeight.isFinite, imageHeight > 0 else { return 0.004 }
        return max(Float.leastNormalMagnitude,2/imageHeight)
    }
    public static func maxSpacingFor(imageHeight: Float) -> Float {
        guard imageHeight.isFinite, imageHeight > 0 else { return .greatestFiniteMagnitude }
        return max(Float.leastNormalMagnitude,4/imageHeight)
    }
}

public enum PumpStamps {
    public static func at(tool: BrushTool, u: Float, v: Float, tick: Int) -> Stamp {
        precondition(tick >= 1)
        if tool.chirality != 0 { return Stamp(cx: u,cy: v,dx: tool.chirality) }
        guard tool == .melt else { return Stamp(cx: u,cy: v) }
        let wander = ValueNoise.at(x: u*40,y: 0,seed: 4)
        return Stamp(cx: u,cy: v,dy: min(Float(tick)*0.0009,0.02)*(0.35+0.65*wander))
    }
    public static func firstPumpTick(tool: BrushTool) -> Int { tool.stampsOnDown ? 2 : 1 }
}

/// The wrapping integer hash is identical to Android's CPU and shader hash.
public enum ValueNoise {
    public static func hash(x: UInt32, y: UInt32, seed: UInt32) -> Float {
        var h = (x &* 1_664_525) &+ (y &* 1_013_904_223) &+ (seed &* 2_654_435_761)
        h ^= h >> 16; h = h &* 2_246_822_519; h ^= h >> 13
        return Float(h & 0x00FF_FFFF)/16_777_216
    }
    public static func at(x: Float, y: Float, seed: UInt32) -> Float {
        guard x.isFinite, y.isFinite else { return 0 }
        let (x0,fx) = lattice(x), (y0,fy) = lattice(y)
        let sx = fx*fx*(3-2*fx), sy = fy*fy*(3-2*fy)
        let a = hash(x: UInt32(bitPattern:x0),y: UInt32(bitPattern:y0),seed: seed)
        let b = hash(x: UInt32(bitPattern:x0 &+ 1),y: UInt32(bitPattern:y0),seed: seed)
        let c = hash(x: UInt32(bitPattern:x0),y: UInt32(bitPattern:y0 &+ 1),seed: seed)
        let d = hash(x: UInt32(bitPattern:x0 &+ 1),y: UInt32(bitPattern:y0 &+ 1),seed: seed)
        return (a+(b-a)*sx) + ((c+(d-c)*sx)-(a+(b-a)*sx))*sy
    }
    private static func lattice(_ value: Float) -> (Int32,Float) {
        let cell = floor(value)
        // Kotlin Float.toInt saturates; Swift's conversion traps. Outside
        // the lattice range use that boundary cell without extrapolating
        // smoothstep, whose fraction is only defined inside a single cell.
        if Double(cell) > Double(Int32.max) { return (Int32.max,0) }
        if Double(cell) < Double(Int32.min) { return (Int32.min,0) }
        let coordinate = Int32(cell)
        return (coordinate,value-Float(coordinate))
    }
}

public enum GooWhip {
    public static func tail(u: Float, v: Float, velU: Float, velV: Float, aspect: Float) -> [(Float,Float)] {
        guard aspect.isFinite, aspect > 0 else { return [] }
        let ax = velU*aspect, ay = velV, raw = hypot(ax,ay)
        guard raw.isFinite, raw >= 0.8 else { return [] }
        let quantized = (min(raw,8)/0.25).rounded()*0.25
        guard quantized >= 0.8 else { return [] }
        var vx = ax*quantized/raw, vy = ay*quantized/raw, x = u*aspect, y = v
        var result: [(Float,Float)] = []
        for _ in 0..<64 {
            x += vx/60; y += vy/60; result.append((x/aspect,y))
            vx *= 0.88; vy *= 0.88
            if hypot(vx,vy) < 0.15 { break }
        }
        return result
    }
}

public struct PortalPair: Equatable, Sendable {
    public var au: Float, av: Float, bu: Float, bv: Float
    public init(au: Float,av: Float,bu: Float,bv: Float) { self.au = au; self.av = av; self.bu = bu; self.bv = bv }
}

public enum Portals {
    public static func separated(au: Float,av: Float,bu: Float,bv: Float,radius: Float,aspect: Float) -> Bool { hypot((bu-au)*aspect,bv-av) >= radius }
    public static func shiftAt(u: Float,v: Float,radius: Float,aspect: Float,pair: PortalPair) -> (Float,Float)? {
        let da = hypot((u-pair.au)*aspect,v-pair.av), db = hypot((u-pair.bu)*aspect,v-pair.bv)
        if da <= radius && (db > radius || da <= db) { return (pair.bu-pair.au,pair.bv-pair.av) }
        if db <= radius { return (pair.au-pair.bu,pair.av-pair.bv) }
        return nil
    }
    public static func expand(stamp: Stamp,shift: (Float,Float)?) -> [Stamp] {
        guard let shift else { return [stamp] }
        return [stamp,Stamp(cx: stamp.cx+shift.0,cy: stamp.cy+shift.1,dx: stamp.dx,dy: stamp.dy)]
    }
}

public enum EchoOffset {
    public static func delta(startU: Float,startV: Float,anchorU: Float,anchorV: Float) -> (Float,Float) { (startU-anchorU,startV-anchorV) }
    public static func isUseful(startU: Float,startV: Float,anchorU: Float,anchorV: Float) -> Bool {
        let du = startU-anchorU, dv = startV-anchorV
        return du*du+dv*dv >= 0.0001
    }
}

public enum PinPull {
    public static let maxHolds = 5
    public static func nearestHold(holds: [(Float,Float)],u: Float,v: Float,aspect: Float) -> Int? {
        var result: Int?, distance: Float = .greatestFiniteMagnitude
        for (i,hold) in holds.enumerated() {
            let d = hypot((u-hold.0)*aspect,v-hold.1)
            if d <= 0.05 && d < distance { result = i; distance = d }
        }
        return result
    }
    public static func warpFor(holds: [(Float,Float)],puck: MlsControl,reach: Float = 1,rubber: Float = 0,aspect: Float = 1) -> PinWarp? {
        guard puck.isFinite, hypot((puck.tu-puck.su)*aspect,puck.tv-puck.sv) >= 0.015 else { return nil }
        let corners = [(Float(0),Float(0)),(1,0),(0,1),(1,1)].map { MlsControl(su: $0.0,sv: $0.1,tu: $0.0,tv: $0.1,weight: 0.15) }
        let controls = corners + holds.prefix(maxHolds).map { MlsControl(su:$0.0,sv:$0.1,tu:$0.0,tv:$0.1) } + [puck]
        let warp = PinWarp(controls: controls,reach: max(0.5,min(3,reach)),rubber: max(0,min(1,rubber)))
        return warp.isValid ? warp : nil
    }
}

public enum GoovieTimeline {
    public static let secondsPerSegment: Float = 1.2
    public static func segment(_ p: Float,size: Int) -> Int { size < 2 ? 0 : max(0,min(size-2,Int(p))) }
    public static func fraction(_ p: Float,size: Int) -> Float { size < 2 ? 0 : max(0,min(1,p-Float(segment(p,size: size)))) }
    public static func clamp(_ p: Float,size: Int) -> Float { max(0,min(Float(max(0,size-1)),p)) }
    public static func advance(_ p: Float,dtSeconds: Float,size: Int) -> Float {
        guard size >= 2 else { return 0 }
        let next = p+dtSeconds/secondsPerSegment, span = Float(size-1)
        return next >= span ? next.truncatingRemainder(dividingBy: span) : next
    }
}

public enum MovieSpeed: Float, CaseIterable, Identifiable, Sendable {
    case half = 0.5, normal = 1, double = 2, quadruple = 4
    public var id: Float { rawValue }
    public var multiplier: Float { rawValue }
    public var title: String { switch self { case .half: "½×"; case .normal: "1×"; case .double: "2×"; case .quadruple: "4×" } }
}

public struct MovieSpec: Sendable {
    public var keyframeCount: Int
    public var frameRate: Int
    public var speed: MovieSpeed
    public init(keyframeCount: Int,frameRate: Int = 30,speed: MovieSpeed = .normal) { precondition(frameRate > 0); self.keyframeCount = keyframeCount; self.frameRate = frameRate; self.speed = speed }
    public var totalFrames: Int { keyframeCount < 2 ? 0 : max(1,Int((Float(keyframeCount-1)*GoovieTimeline.secondsPerSegment/speed.multiplier*Float(frameRate)).rounded()))+1 }
    public var durationSeconds: Float { totalFrames < 2 ? 0 : Float(totalFrames-1)/Float(frameRate) }
    public func timelinePosition(frame: Int) -> Float { totalFrames < 2 ? 0 : Float(keyframeCount-1)*Float(frame)/Float(totalFrames-1) }
    public static func gifFPS(keyframeCount: Int,speed: MovieSpeed = .normal) -> Int {
        [20,10,5,4,2].first { Self(keyframeCount:keyframeCount,frameRate:$0,speed:speed).totalFrames <= 200 } ?? 2
    }
    public static func videoSize(width: Int,height: Int,maxDimension: Int = 1920) -> (Int,Int) {
        precondition(width > 0 && height > 0 && maxDimension >= 2)
        let scale = min(1,Float(maxDimension)/Float(max(width,height)))
        let w = max(2,Int(Float(width)*scale)), h = max(2,Int(Float(height)*scale))
        return (w-w%2,h-h%2)
    }
}
