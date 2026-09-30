import Foundation

public struct GooDeal: Sendable {
    public var strokes: [Stroke]
    public var globals: GlobalParams
}

/// The same ten authored recipes and xorshift64 generator as Android. A deal
/// produces ordinary recorded edits; persistence never depends on an RNG.
public enum GooMe {
    private enum Landmark {
        case brow, eyeL, eyeR, nose, mouth, chin, cheekL, cheekR
        var position: (Float,Float) {
            switch self {
            case .brow: (0,-0.17); case .eyeL: (-0.1,-0.06); case .eyeR: (0.1,-0.06)
            case .nose: (0,0.04); case .mouth: (0,0.16); case .chin: (0,0.28)
            case .cheekL: (-0.16,0.1); case .cheekR: (0.16,0.1)
            }
        }
    }
    private struct Move {
        var tool: BrushTool, at: Landmark, radius: ClosedRange<Float>, strength: ClosedRange<Float>
        var hold: ClosedRange<Int> = 0...0
        var heading: ClosedRange<Float> = 0...0, length: ClosedRange<Float> = 0...0, sweep: ClosedRange<Float> = 0...0
        init(_ tool: BrushTool,_ at: Landmark,_ radius: ClosedRange<Float>,_ strength: ClosedRange<Float>,hold: ClosedRange<Int> = 0...0,heading: ClosedRange<Float> = 0...0,length: ClosedRange<Float> = 0...0,sweep: ClosedRange<Float> = 0...0) {
            self.tool=tool; self.at=at; self.radius=radius; self.strength=strength
            self.hold=hold; self.heading=heading; self.length=length; self.sweep=sweep
        }
    }
    private struct LeverPull {
        var index: Int, value: ClosedRange<Float>, eitherWay: Bool
        init(_ index: Int,_ value: ClosedRange<Float>,eitherWay: Bool = false) { self.index=index; self.value=value; self.eitherWay=eitherWay }
    }
    private struct Recipe {
        var moves: [Move], lever: LeverPull?
        init(_ moves: [Move],_ lever: LeverPull? = nil) { self.moves=moves; self.lever=lever }
    }
    private static let deck: [Recipe] = [
        Recipe([Move(.grow,.eyeL,0.07...0.10,0.6...0.9,hold:22...34),Move(.grow,.eyeR,0.07...0.10,0.6...0.9,hold:22...34),Move(.nudge,.mouth,0.10...0.14,0.7...1,heading:250...290,length:0.10...0.16)]),
        Recipe([Move(.smear,.cheekL,0.10...0.15,0.5...0.8,heading:160...200,length:0.16...0.26,sweep:10...40),Move(.smear,.cheekR,0.10...0.15,0.5...0.8,heading:-20...20,length:0.16...0.26,sweep:10...40)],LeverPull(3,0.25...0.5)),
        Recipe([Move(.vortex,.cheekL,0.10...0.15,0.6...0.9,hold:26...40),Move(.grow,.nose,0.08...0.12,0.5...0.7,hold:14...22)],LeverPull(1,0.12...0.28,eitherWay:true)),
        Recipe([Move(.melt,.chin,0.10...0.16,0.7...1,hold:45...75),Move(.melt,.mouth,0.08...0.12,0.6...0.9,hold:30...55),Move(.smooth,.brow,0.10...0.14,0.5...0.8,hold:5...9)]),
        Recipe([Move(.shrink,.brow,0.12...0.18,0.6...0.9,hold:24...38),Move(.grow,.chin,0.10...0.15,0.5...0.8,hold:18...30)],LeverPull(2,0.2...0.4)),
        Recipe([Move(.comb,.brow,0.08...0.12,0.7...1,heading:250...270,length:0.14...0.22,sweep:0...25),Move(.comb,.brow,0.08...0.12,0.7...1,heading:270...290,length:0.14...0.22,sweep:0...25)],LeverPull(4,0.3...0.6)),
        Recipe([Move(.pond,.nose,0.12...0.18,0.6...0.9,hold:1...1),Move(.pond,.cheekR,0.09...0.14,0.5...0.8,hold:1...1)],LeverPull(0,0.15...0.3)),
        Recipe([Move(.fault,.mouth,0.08...0.12,0.7...1,heading:-15...15,length:0.24...0.36),Move(.smudge,.chin,0.10...0.16,0.6...0.9,heading:60...120,length:0.08...0.14)]),
        Recipe([Move(.move,.cheekL,0.08...0.12,0.5...0.8,heading:200...240,length:0.10...0.16,sweep:20...50),Move(.move,.cheekR,0.08...0.12,0.5...0.8,heading:-60 ... -20,length:0.10...0.16,sweep:20...50),Move(.grow,.mouth,0.09...0.13,0.4...0.7,hold:12...20)]),
        Recipe([Move(.unwind,.nose,0.12...0.18,0.7...1,hold:30...46),Move(.vortex,.brow,0.09...0.14,0.5...0.8,hold:20...32)],LeverPull(1,0.2...0.4,eitherWay:true))
    ]

    public static func deal(seed: UInt64,aspect: Float) -> [Stroke] { makeDeal(seed:seed,aspect:aspect).strokes }
    public static func makeDeal(seed: UInt64,aspect: Float,from: GlobalParams = GlobalParams()) -> GooDeal {
        precondition(aspect.isFinite && aspect > 0)
        var dice = Dice(seed: seed)
        let recipe = deck[dice.pick(deck.count)]
        var strokes: [Stroke] = []
        for move in recipe.moves {
            let radius = dice.range(move.radius), strength = dice.range(move.strength)*move.tool.strengthScale
            let p = move.at.position
            let u = max(0.03,min(0.97,0.5+(p.0+dice.signed()*0.025)/aspect))
            let v = max(0.03,min(0.97,0.44+p.1+dice.signed()*0.025))
            var stamps: [Stamp] = []
            if move.hold.upperBound > 0 {
                let ticks = move.hold.lowerBound+dice.pick(move.hold.upperBound-move.hold.lowerBound+1)
                for tick in 1...ticks { stamps.append(PumpStamps.at(tool:move.tool,u:u,v:v,tick:tick)) }
            } else {
                let heading = dice.range(move.heading)*(.pi/180), length = dice.range(move.length), sweep = dice.range(move.sweep)*(.pi/180)
                let resampler = StrokeResampler(radius:radius,aspect:aspect)
                resampler.begin(u:u,v:v)
                if move.tool.stampsOnDown { stamps.append(PumpStamps.at(tool:move.tool,u:u,v:v,tick:1)) }
                var ax = u*aspect, ay = v
                for i in 1...32 {
                    let turn = heading+sweep*((Float(i)-0.5)/32-0.5)
                    ax += cos(turn)*length/32; ay += sin(turn)*length/32
                    stamps += resampler.extend(u:max(0.03,min(0.97,ax/aspect)),v:max(0.03,min(0.97,ay)))
                }
            }
            if !stamps.isEmpty { strokes.append(Stroke(tool:move.tool,radius:radius,strength:strength,stamps:stamps)) }
        }
        var globals = from
        if let lever = recipe.lever {
            let magnitude = dice.range(lever.value)
            globals[lever.index] = max(-1,min(1,magnitude*(lever.eitherWay ? dice.sign() : 1)))
        }
        return GooDeal(strokes: strokes,globals:globals)
    }
    private struct Dice {
        private var state: UInt64
        init(seed: UInt64) {
            var z = seed &+ 0x9E3779B97F4A7C15
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z ^= z >> 31
            state = z == 0 ? 0x9E3779B97F4A7C15 : z
        }
        mutating func next() -> Float {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(state >> 40)/16_777_216
        }
        mutating func pick(_ count: Int) -> Int { max(0,min(count-1,Int(next()*Float(count)))) }
        mutating func signed() -> Float { next()*2-1 }
        mutating func sign() -> Float { next() < 0.5 ? -1 : 1 }
        mutating func range(_ range: ClosedRange<Float>) -> Float { range.lowerBound+next()*(range.upperBound-range.lowerBound) }
    }
}

public enum DealLevers {
    public static func draw(seed: UInt64,from: GlobalParams = GlobalParams()) -> GlobalParams {
        GooMe.makeDeal(seed:seed,aspect:1,from:from).globals
    }
}
