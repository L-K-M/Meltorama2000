import Foundation

// Wire names deliberately match Android's project.json. Coordinates are source
// UV, origin top-left; radii measure fractions of the upright image's height.
public enum StampMode: Int, Sendable {
    case directional = 0, inflate, deflate, relax, erase, fuse, vortex, comb, ripple, fault, guardMask, recall, pinwarp
    public var mirrorsDelta: Bool { [.directional, .vortex, .comb, .fault].contains(self) }
    public var rotatesDelta: Bool { [.directional, .comb, .fault].contains(self) }
}

public enum FalloffProfile: Int, Sendable { case smoothstep = 0, feather, plateau, drip }

public enum BrushTool: String, Codable, CaseIterable, Identifiable, Sendable {
    case smear = "SMEAR", move = "MOVE", smudge = "SMUDGE", nudge = "NUDGE"
    case grow = "GROW", shrink = "SHRINK", smooth = "SMOOTH", ungoo = "UNGOO"
    case fuse = "FUSE", vortex = "VORTEX", unwind = "UNWIND", melt = "MELT"
    case comb = "COMB", pond = "POND", fault = "FAULT", echo = "ECHO"
    case whip = "WHIP", freeze = "FREEZE", rewind = "REWIND", pins = "PINS"

    public var id: String { rawValue }
    public var title: String { switch self { case .ungoo: "UnGoo"; case .fuse: "Fusion"; case .pins: "Taffy Pins"; default: rawValue.capitalized } }
    public var mode: StampMode {
        switch self {
        case .grow: .inflate
        case .shrink: .deflate
        case .smooth: .relax
        case .ungoo: .erase
        case .fuse: .fuse
        case .vortex, .unwind: .vortex
        case .comb: .comb
        case .pond: .ripple
        case .fault: .fault
        case .freeze: .guardMask
        case .rewind: .recall
        case .pins: .pinwarp
        default: .directional
        }
    }
    public var profile: FalloffProfile {
        switch self { case .smudge, .echo, .whip, .freeze: .feather; case .move: .plateau; case .melt: .drip; default: .smoothstep }
    }
    public var strengthScale: Float { switch self { case .smudge: 0.45; case .nudge: 0.15; default: 1 } }
    public var pumped: Bool { [.grow, .shrink, .smooth, .ungoo, .vortex, .unwind, .melt, .rewind].contains(self) }
    public var stampsOnDown: Bool { pumped || [.fuse, .pond, .freeze].contains(self) }
    public var needsTarget: Bool { self == .rewind }
    public var isPinWarp: Bool { self == .pins }
    public var chirality: Float { switch self { case .vortex: 1; case .unwind: -1; default: 0 } }
    public func mirrorStamp(_ stamp: Stamp) -> Stamp {
        Stamp(cx: 1 - stamp.cx, cy: stamp.cy, dx: mode.mirrorsDelta ? -stamp.dx : stamp.dx, dy: stamp.dy)
    }
}

public struct Stamp: Codable, Equatable, Sendable {
    public var cx: Float
    public var cy: Float
    public var dx: Float
    public var dy: Float
    public init(cx: Float, cy: Float, dx: Float = 0, dy: Float = 0) { self.cx = cx; self.cy = cy; self.dx = dx; self.dy = dy }
    public var isFinite: Bool { cx.isFinite && cy.isFinite && dx.isFinite && dy.isFinite }
}

public struct MlsControl: Codable, Equatable, Sendable {
    public var su: Float
    public var sv: Float
    public var tu: Float
    public var tv: Float
    public var weight: Float
    public init(su: Float, sv: Float, tu: Float, tv: Float, weight: Float = 1) {
        self.su = su; self.sv = sv; self.tu = tu; self.tv = tv; self.weight = weight
    }
    public var isFinite: Bool { su.isFinite && sv.isFinite && tu.isFinite && tv.isFinite && weight.isFinite && weight > 0 }
    private enum CodingKeys: String, CodingKey { case su, sv, tu, tv, weight }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        su = try c.decode(Float.self, forKey: .su); sv = try c.decode(Float.self, forKey: .sv)
        tu = try c.decode(Float.self, forKey: .tu); tv = try c.decode(Float.self, forKey: .tv)
        weight = try c.decodeIfPresent(Float.self, forKey: .weight) ?? 1
    }
}

public struct PinWarp: Codable, Equatable, Sendable {
    public static let maxControls = 10
    public var controls: [MlsControl]
    public var reach: Float
    public var rubber: Float
    public var solverVersion: Int
    public init(controls: [MlsControl], reach: Float = 1, rubber: Float = 0, solverVersion: Int = 1) {
        self.controls = controls; self.reach = reach; self.rubber = rubber; self.solverVersion = solverVersion
    }
    public var isValid: Bool {
        !controls.isEmpty && controls.count <= Self.maxControls && controls.allSatisfy(\.isFinite) &&
        reach.isFinite && rubber.isFinite && solverVersion == 1 && controls.contains { $0.su != $0.tu || $0.sv != $0.tv }
    }
    private enum CodingKeys: String, CodingKey { case controls, reach, rubber, solverVersion }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        controls = try c.decode([MlsControl].self, forKey: .controls)
        reach = try c.decodeIfPresent(Float.self, forKey: .reach) ?? 1
        rubber = try c.decodeIfPresent(Float.self, forKey: .rubber) ?? 0
        solverVersion = try c.decodeIfPresent(Int.self, forKey: .solverVersion) ?? 1
    }
}

public struct Stroke: Codable, Equatable, Sendable {
    public var tool: BrushTool
    public var radius: Float
    public var strength: Float
    public var stamps: [Stamp]
    public var targetRevision: Int64?
    public var pinWarp: PinWarp?
    public init(tool: BrushTool, radius: Float, strength: Float, stamps: [Stamp] = [], targetRevision: Int64? = nil, pinWarp: PinWarp? = nil) {
        self.tool = tool; self.radius = radius; self.strength = strength; self.stamps = stamps
        self.targetRevision = targetRevision; self.pinWarp = pinWarp
    }
    public var hasContent: Bool { !stamps.isEmpty || pinWarp != nil }
    public var isCoherent: Bool { stamps.isEmpty || pinWarp == nil }
    public var isValid: Bool {
        hasContent && isCoherent && radius.isFinite && radius > 0 && strength.isFinite &&
        stamps.allSatisfy(\.isFinite) && (pinWarp?.isValid ?? true) &&
        (pinWarp != nil) == tool.isPinWarp && tool.needsTarget == (targetRevision != nil)
    }
    private enum CodingKeys: String, CodingKey { case tool, radius, strength, stamps, targetRevision, pinWarp }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decode(BrushTool.self, forKey: .tool)
        radius = try c.decode(Float.self, forKey: .radius); strength = try c.decode(Float.self, forKey: .strength)
        stamps = try c.decodeIfPresent([Stamp].self, forKey: .stamps) ?? []
        targetRevision = try c.decodeIfPresent(Int64.self, forKey: .targetRevision)
        pinWarp = try c.decodeIfPresent(PinWarp.self, forKey: .pinWarp)
    }
}

public enum LensType: String, Codable, CaseIterable, Identifiable, Sendable {
    case bulge = "BULGE", pinch = "PINCH", fisheye = "FISHEYE", vortex = "VORTEX"
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var shaderID: Int { switch self { case .bulge: 0; case .pinch: 1; case .fisheye: 2; case .vortex: 3 } }
}

public struct Lens: Codable, Equatable, Sendable {
    public static let capacity = 4
    public var u: Float
    public var v: Float
    public var radius: Float
    public var type: LensType
    public var strength: Float
    public init(u: Float = 0.5, v: Float = 0.5, radius: Float = 0.18, type: LensType = .bulge, strength: Float = 0.6) {
        self.u = u; self.v = v; self.radius = radius; self.type = type; self.strength = strength
    }
    public var isIdentity: Bool { strength == 0 }
    public var isValid: Bool { [u, v, radius, strength].allSatisfy(\.isFinite) && (0...1).contains(u) && (0...1).contains(v) && radius > 0 && (-1...1).contains(strength) }
    private enum CodingKeys: String, CodingKey { case u, v, radius, type, strength }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        u = try c.decode(Float.self, forKey: .u); v = try c.decode(Float.self, forKey: .v)
        radius = try c.decodeIfPresent(Float.self, forKey: .radius) ?? 0.18
        type = try c.decodeIfPresent(LensType.self, forKey: .type) ?? .bulge
        strength = try c.decodeIfPresent(Float.self, forKey: .strength) ?? 0.6
    }
}

public struct GlobalParams: Codable, Equatable, Sendable {
    public var bulge: Float
    public var twirl: Float
    public var squeeze: Float
    public var stretch: Float
    public var spike: Float
    public var `static`: Float
    public var lenses: [Lens]
    public init(bulge: Float = 0, twirl: Float = 0, squeeze: Float = 0, stretch: Float = 0, spike: Float = 0, static: Float = 0, lenses: [Lens] = []) {
        self.bulge = bulge; self.twirl = twirl; self.squeeze = squeeze; self.stretch = stretch
        self.spike = spike; self.static = `static`; self.lenses = lenses
    }
    public var values: [Float] { [bulge, twirl, squeeze, stretch, spike, `static`] }
    public var isIdentity: Bool { values.allSatisfy { $0 == 0 } && lenses.allSatisfy(\.isIdentity) }
    public var isValid: Bool { values.allSatisfy { $0.isFinite && (-1...1).contains($0) } && lenses.count <= Lens.capacity && lenses.allSatisfy(\.isValid) }
    public subscript(index: Int) -> Float {
        get { values[index] }
        set { switch index { case 0: bulge = newValue; case 1: twirl = newValue; case 2: squeeze = newValue; case 3: stretch = newValue; case 4: spike = newValue; case 5: `static` = newValue; default: break } }
    }
    public mutating func setValue(_ value: Float, at index: Int) { self[index] = value }
    public func lerp(_ other: Self, t: Float) -> Self {
        var result = self
        for i in 0..<6 { result[i] = self[i] + (other[i] - self[i]) * t }
        result.lenses = (0..<max(lenses.count, other.lenses.count)).map { i in
            let a = i < lenses.count ? lenses[i] : nil
            let b = i < other.lenses.count ? other.lenses[i] : nil
            if let a, let b {
                return Lens(u: a.u + (b.u-a.u)*t, v: a.v + (b.v-a.v)*t, radius: a.radius + (b.radius-a.radius)*t, type: t < 0.5 ? a.type : b.type, strength: a.strength + (b.strength-a.strength)*t)
            }
            if var a { a.strength *= 1-t; return a }
            var value = b!; value.strength *= t; return value
        }
        return result
    }
    private enum CodingKeys: String, CodingKey { case bulge, twirl, squeeze, stretch, spike, `static`, lenses }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bulge = try c.decodeIfPresent(Float.self, forKey: .bulge) ?? 0
        twirl = try c.decodeIfPresent(Float.self, forKey: .twirl) ?? 0
        squeeze = try c.decodeIfPresent(Float.self, forKey: .squeeze) ?? 0
        stretch = try c.decodeIfPresent(Float.self, forKey: .stretch) ?? 0
        spike = try c.decodeIfPresent(Float.self, forKey: .spike) ?? 0
        `static` = try c.decodeIfPresent(Float.self, forKey: .static) ?? 0
        lenses = try c.decodeIfPresent([Lens].self, forKey: .lenses) ?? []
    }
}

public struct LeverWobble: Codable, Equatable, Sendable {
    public var rate: Int
    public var depth: Float
    public init(rate: Int = 0, depth: Float = 0) { self.rate = rate; self.depth = depth }
    public var isStill: Bool { rate == 0 || depth == 0 }
    private enum CodingKeys: String, CodingKey { case rate, depth }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rate = try c.decodeIfPresent(Int.self, forKey: .rate) ?? 0
        depth = try c.decodeIfPresent(Float.self, forKey: .depth) ?? 0
    }
}

public struct GlobalWobble: Codable, Equatable, Sendable {
    public var levers: [LeverWobble]
    public init(levers: [LeverWobble] = Array(repeating: LeverWobble(), count: 6)) { self.levers = levers }
    public var isStill: Bool { levers.allSatisfy(\.isStill) }
    public func sanitized() -> Self {
        Self(levers: (0..<6).map { i in
            let l = i < levers.count ? levers[i] : LeverWobble()
            return LeverWobble(rate: max(0,min(8,l.rate)), depth: l.depth.isFinite ? max(0,min(1,l.depth)) : 0)
        })
    }
    public static func maxSafeRate(loopSeconds: Float) -> Int {
        guard loopSeconds.isFinite, loopSeconds > 0 else { return 0 }
        return Int(max(0,min(8,floor(3*loopSeconds))))
    }
    public func cappedFor(loopSeconds: Float) -> Self {
        let limit = Self.maxSafeRate(loopSeconds: loopSeconds)
        return Self(levers: sanitized().levers.map { LeverWobble(rate: min(limit,$0.rate), depth: $0.depth) })
    }
    private enum CodingKeys: String, CodingKey { case levers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levers = try c.decodeIfPresent([LeverWobble].self, forKey: .levers) ?? Array(repeating: LeverWobble(), count: 6)
    }
}

public func leversAt(base: GlobalParams, wobble: GlobalWobble, phase: Float) -> GlobalParams {
    guard !wobble.isStill else { return base }
    var result = base
    for (i, lever) in wobble.levers.prefix(6).enumerated() where !lever.isStill {
        result[i] = max(-1,min(1,result[i] + lever.depth*sin(2 * .pi * Float(lever.rate) * phase)))
    }
    return result
}

public struct CropRect: Codable, Equatable, Sendable {
    public var left: Float
    public var top: Float
    public var right: Float
    public var bottom: Float
    public init(left: Float, top: Float, right: Float, bottom: Float) { self.left = left; self.top = top; self.right = right; self.bottom = bottom }
    public static let full = Self(left: 0, top: 0, right: 1, bottom: 1)
    public var width: Float { right-left }
    public var height: Float { bottom-top }
    public var isFullFrame: Bool { left <= 0.005 && top <= 0.005 && right >= 0.995 && bottom >= 0.995 }
    public var isValid: Bool { [left,top,right,bottom].allSatisfy { $0.isFinite && (0...1).contains($0) } && width > 0 && height > 0 }
    public func compose(_ inner: Self) -> Self { Self(left: left+inner.left*width,top: top+inner.top*height,right: left+inner.right*width,bottom: top+inner.bottom*height) }

    public struct PixelRect: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
    }

    /// Android rounds Float products before clamping. Rounding each origin
    /// and size independently preserves its crop pixels and export dimensions.
    public func pixelRect(width imageWidth: Int, height imageHeight: Int) throws -> PixelRect {
        guard isValid, imageWidth > 0, imageHeight > 0,
              imageWidth <= Int32.max, imageHeight <= Int32.max else { throw ProjectError.invalidCrop }
        let x = min(imageWidth - 1, max(0, Int((left * Float(imageWidth)).rounded(.toNearestOrAwayFromZero))))
        let y = min(imageHeight - 1, max(0, Int((top * Float(imageHeight)).rounded(.toNearestOrAwayFromZero))))
        let pixelWidth = min(imageWidth - x, max(1, Int((width * Float(imageWidth)).rounded(.toNearestOrAwayFromZero))))
        let pixelHeight = min(imageHeight - y, max(1, Int((height * Float(imageHeight)).rounded(.toNearestOrAwayFromZero))))
        return PixelRect(x: x, y: y, width: pixelWidth, height: pixelHeight)
    }
}

public enum Easing: String, Codable, CaseIterable, Identifiable, Sendable {
    case linear = "LINEAR", ease = "EASE", boing = "BOING"
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public func at(_ p: Float) -> Float {
        let t = max(0,min(1,p))
        switch self {
        case .linear: return t
        case .ease: return t*t*(3-2*t)
        case .boing:
            // Force endpoint identities, avoiding Float cancellation at t=0.
            if t == 0 || t == 1 { return t }
            let q = t-1
            return 1 + (1+1.70158)*q*q*q + 1.70158*q*q
        }
    }
}

public func tweenProgress(_ p: Float, easing: Easing) -> Float { max(0,min(1.35,easing.at(p))) }
public func leverProgress(_ p: Float, easing: Easing) -> Float { max(0,min(1,easing.at(p))) }

public struct KeyframeRecord: Codable, Equatable, Sendable {
    public var revision: Int64
    public var globals: GlobalParams
    public var easing: Easing
    public init(revision: Int64, globals: GlobalParams = GlobalParams(), easing: Easing = .linear) { self.revision = revision; self.globals = globals; self.easing = easing }
    private enum CodingKeys: String, CodingKey { case revision, globals, easing }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(Int64.self, forKey: .revision)
        globals = try c.decodeIfPresent(GlobalParams.self, forKey: .globals) ?? GlobalParams()
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .linear
    }
}

public struct StrokeRevisionRecord: Codable, Equatable, Sendable {
    public var id: Int64
    public var parent: Int64?
    public var stroke: Stroke?
    public init(id: Int64, parent: Int64? = nil, stroke: Stroke? = nil) { self.id = id; self.parent = parent; self.stroke = stroke }
}

public struct StrokeLogSnapshot: Codable, Equatable, Sendable {
    public var revisions: [StrokeRevisionRecord]
    public var history: [Int64]
    public var cursor: Int
    public init(revisions: [StrokeRevisionRecord] = [StrokeRevisionRecord(id: 0)], history: [Int64] = [0], cursor: Int = 0) { self.revisions = revisions; self.history = history; self.cursor = cursor }
    public var currentRevision: Int64 { history.indices.contains(cursor) ? history[cursor] : 0 }
    public var canUndo: Bool { cursor > 0 }
    public var canRedo: Bool { cursor < history.count-1 }
    public func validate() throws {
        guard !history.isEmpty, history.indices.contains(cursor) else { throw ProjectError.invalidHistory }
        var seen = Set<Int64>()
        for r in revisions {
            guard r.id >= 0, r.id < Int64.max, !seen.contains(r.id) else { throw ProjectError.invalidRevision(r.id) }
            if let parent = r.parent { guard parent < r.id, seen.contains(parent) else { throw ProjectError.invalidRevision(r.id) } }
            if let stroke = r.stroke {
                guard stroke.isValid else { throw ProjectError.invalidStroke(r.id) }
                if let target = stroke.targetRevision { guard target < r.id, seen.contains(target) else { throw ProjectError.invalidRevision(r.id) } }
            }
            seen.insert(r.id)
        }
        guard history.allSatisfy(seen.contains) else { throw ProjectError.invalidHistory }
    }
    public func materialize(revision: Int64? = nil) throws -> [Stroke] {
        try validate()
        let table = Dictionary(uniqueKeysWithValues: revisions.map { ($0.id,$0) })
        let requested = revision ?? currentRevision
        guard table[requested] != nil else { throw ProjectError.invalidRevision(requested) }
        var result: [Stroke] = []
        var next: Int64? = requested
        while let id = next, let record = table[id] {
            if let stroke = record.stroke { result.append(stroke) }
            next = record.parent
        }
        return result.reversed()
    }
    private enum CodingKeys: String, CodingKey { case revisions, history, cursor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revisions = try c.decodeIfPresent([StrokeRevisionRecord].self, forKey: .revisions) ?? [StrokeRevisionRecord(id: 0)]
        history = try c.decodeIfPresent([Int64].self, forKey: .history) ?? [0]
        cursor = try c.decodeIfPresent(Int.self, forKey: .cursor) ?? 0
    }
}

// A value type integrates naturally with NSUndoManager snapshots. IDs remain
// monotonic while branch roots retained by movie pins survive undo/new strokes.
public struct StrokeLog: Sendable {
    private var state: StrokeLogSnapshot
    private var nextRevision: Int64
    public init() { state = StrokeLogSnapshot(); nextRevision = 1 }
    public init(snapshot: StrokeLogSnapshot) throws { try snapshot.validate(); state = snapshot; nextRevision = (snapshot.revisions.map(\.id).max() ?? 0)+1 }
    public var currentRevision: Int64 { state.currentRevision }
    public var strokes: [Stroke] { (try? state.materialize()) ?? [] }
    public var canUndo: Bool { state.canUndo }
    public var canRedo: Bool { state.canRedo }
    public mutating func push(_ stroke: Stroke) throws {
        guard stroke.hasContent else { return }
        guard stroke.isValid else { throw ProjectError.invalidStroke(nextRevision) }
        if let target = stroke.targetRevision { guard state.revisions.contains(where: { $0.id == target }) else { throw ProjectError.invalidRevision(target) } }
        state.history = Array(state.history.prefix(state.cursor+1))
        state.revisions.append(StrokeRevisionRecord(id: nextRevision,parent: currentRevision,stroke: stroke))
        state.history.append(nextRevision); state.cursor += 1; nextRevision += 1
    }
    public mutating func pushBatch(_ strokes: [Stroke]) throws {
        let batch = strokes.filter(\.hasContent)
        guard !batch.isEmpty else { return }
        guard batch.allSatisfy({ $0.isValid && $0.pinWarp == nil }) else { throw ProjectError.invalidStroke(nextRevision) }
        var draft = self
        let startingHistory = Array(draft.state.history.prefix(draft.state.cursor+1))
        for stroke in batch { try draft.push(stroke) }
        draft.state.history = startingHistory + [draft.currentRevision]
        draft.state.cursor = startingHistory.count
        self = draft
    }
    public mutating func undo() { if canUndo { state.cursor -= 1 } }
    public mutating func redo() { if canRedo { state.cursor += 1 } }
    public mutating func reset() {
        guard !strokes.isEmpty else { return }
        state.history = Array(state.history.prefix(state.cursor+1))
        state.revisions.append(StrokeRevisionRecord(id: nextRevision))
        state.history.append(nextRevision); state.cursor += 1; nextRevision += 1
    }
    public mutating func clearHistory() {
        state = StrokeLogSnapshot(revisions: [StrokeRevisionRecord(id: nextRevision)],history: [nextRevision]); nextRevision += 1
    }
    public func snapshot(pins: [Int64] = []) -> StrokeLogSnapshot {
        let table = Dictionary(uniqueKeysWithValues: state.revisions.map { ($0.id,$0) })
        var pending = state.history + pins
        var retained = Set<Int64>()
        while let id = pending.popLast() {
            guard retained.insert(id).inserted, let revision = table[id] else { continue }
            if let parent = revision.parent { pending.append(parent) }
            if let target = revision.stroke?.targetRevision { pending.append(target) }
        }
        return StrokeLogSnapshot(revisions: state.revisions.filter { retained.contains($0.id) },history: state.history,cursor: state.cursor)
    }
}

public struct ProjectDocument: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schema: Int
    public var updatedAtMillis: Int64
    public var source: String
    public var fusion: String?
    public var crop: CropRect?
    public var globals: GlobalParams
    public var wobble: GlobalWobble
    public var log: StrokeLogSnapshot
    public var keyframes: [KeyframeRecord]
    public init(schema: Int = 1, updatedAtMillis: Int64 = 0, source: String = "source.img", fusion: String? = nil, crop: CropRect? = nil, globals: GlobalParams = GlobalParams(), wobble: GlobalWobble = GlobalWobble(), log: StrokeLogSnapshot = StrokeLogSnapshot(), keyframes: [KeyframeRecord] = []) {
        self.schema = schema; self.updatedAtMillis = updatedAtMillis; self.source = source; self.fusion = fusion
        self.crop = crop; self.globals = globals; self.wobble = wobble; self.log = log; self.keyframes = keyframes
    }
    public func validate() throws {
        guard schema == Self.schemaVersion else { throw ProjectError.unsupportedSchema(schema) }
        guard Self.isLocalName(source), fusion.map(Self.isLocalName) ?? true else { throw ProjectError.invalidAssetName }
        if let fusion {
            // Most Mac volumes compare names without case and normalize
            // Unicode. Two Android assets may otherwise overwrite each other.
            guard Self.filenameKey(fusion) != Self.filenameKey(source) else { throw ProjectError.invalidAssetName }
        }
        if let crop { guard crop.isValid else { throw ProjectError.invalidCrop } }
        guard globals.isValid, keyframes.allSatisfy({ $0.globals.isValid }), keyframes.count <= 64 else { throw ProjectError.invalidGlobals }
        guard wobble.levers.allSatisfy({ $0.depth.isFinite }) else { throw ProjectError.invalidGlobals }
        try log.validate()
        let ids = Set(log.revisions.map(\.id))
        guard keyframes.allSatisfy({ ids.contains($0.revision) }) else { throw ProjectError.invalidKeyframe }
    }
    public static func isLocalName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0") && filenameKey(name) != "project.json"
    }
    private static func filenameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    public static func decode(_ data: Data) throws -> Self {
        var project = try JSONDecoder().decode(Self.self, from: data)
        project.wobble = project.wobble.sanitized()
        try project.validate()
        return project
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    private enum CodingKeys: String, CodingKey { case schema, updatedAtMillis, source, fusion, crop, globals, wobble, log, keyframes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        updatedAtMillis = try c.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "source.img"
        fusion = try c.decodeIfPresent(String.self, forKey: .fusion)
        crop = try c.decodeIfPresent(CropRect.self, forKey: .crop)
        globals = try c.decodeIfPresent(GlobalParams.self, forKey: .globals) ?? GlobalParams()
        wobble = try c.decodeIfPresent(GlobalWobble.self, forKey: .wobble) ?? GlobalWobble()
        log = try c.decodeIfPresent(StrokeLogSnapshot.self, forKey: .log) ?? StrokeLogSnapshot()
        keyframes = try c.decodeIfPresent([KeyframeRecord].self, forKey: .keyframes) ?? []
    }
}

public enum ProjectError: LocalizedError {
    case unsupportedSchema(Int), invalidAssetName, missingAsset(String), invalidHistory
    case invalidRevision(Int64), invalidStroke(Int64), invalidCrop, invalidGlobals, invalidKeyframe, invalidPackage
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema): "This project uses unsupported document version \(schema)."
        case .invalidAssetName: "The project contains an invalid image filename."
        case .missingAsset(let name): "The project's image \(name) is missing."
        case .invalidHistory: "The project's undo history is damaged."
        case .invalidRevision(let id): "The project contains a damaged revision (\(id))."
        case .invalidStroke(let id): "The project contains an invalid brush edit (revision \(id))."
        case .invalidCrop: "The project's crop is invalid."
        case .invalidGlobals: "The project contains invalid effect settings."
        case .invalidKeyframe: "An animation keyframe refers to a missing revision."
        case .invalidPackage: "Choose a Meltorama project package or an Android project folder."
        }
    }
}
