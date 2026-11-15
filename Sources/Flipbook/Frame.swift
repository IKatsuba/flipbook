import Foundation

/// The only input a composition's view may depend on.
///
/// Everything here is a pure function of `index`: no clocks, no state.
public struct Frame: Sendable, Equatable {
    /// Zero-based frame number, local to the current sequence or loop.
    public let index: Int
    /// Frames per second of the composition.
    public let fps: Int
    /// Number of frames in the current sequence, loop or composition.
    public let frames: Int

    public init(index: Int, fps: Int, frames: Int) {
        self.index = index
        self.fps = fps
        self.frames = frames
    }

    /// Seconds since the start of the current sequence.
    public var time: Double { Double(index) / Double(fps) }

    /// 0 at the first frame, 1 at the last.
    public var progress: Double {
        frames > 1 ? Double(index) / Double(frames - 1) : 0
    }

    // MARK: Interpolation

    public enum Extrapolation: Sendable {
        case clamp
        case extend
    }

    /// Maps the frame index from `input` (ascending frame numbers) to `output`,
    /// piecewise, applying `easing` inside every segment.
    public func interpolate(
        _ input: [Double],
        _ output: [Double],
        easing: Easing = .linear,
        extrapolate: Extrapolation = .clamp
    ) -> Double {
        Frame.interpolate(Double(index), input, output, easing: easing, extrapolate: extrapolate)
    }

    public static func interpolate(
        _ value: Double,
        _ input: [Double],
        _ output: [Double],
        easing: Easing = .linear,
        extrapolate: Extrapolation = .clamp
    ) -> Double {
        precondition(input.count == output.count && input.count >= 2, "interpolate needs matching ranges of two or more points")
        var segment = 0
        while segment < input.count - 2 && value > input[segment + 1] { segment += 1 }
        let (x0, x1) = (input[segment], input[segment + 1])
        let (y0, y1) = (output[segment], output[segment + 1])
        guard x1 > x0 else { return value < x0 ? y0 : y1 }
        var t = (value - x0) / (x1 - x0)
        if extrapolate == .clamp { t = min(max(t, 0), 1) }
        let eased = (0...1).contains(t) ? easing.value(t) : t
        return y0 + (y1 - y0) * eased
    }

    // MARK: Spring

    /// A damped spring going from 0 to 1, released at frame `from` and solved in closed form,
    /// so frame N has the same value however it is reached.
    ///
    /// A spring never quite arrives: its tail keeps moving by less than a pixel, and whatever is
    /// positioned with it hops between pixels long after it looks still. `settle` bends the curve
    /// to be exactly 1 that many frames after release, and from then on.
    public func spring(
        from start: Int = 0,
        mass: Double = 1,
        stiffness: Double = 100,
        damping: Double = 10,
        initialVelocity: Double = 0,
        settle: Int? = nil
    ) -> Double {
        let value = { (frames: Int) in
            Frame.springValue(at: Double(frames) / Double(fps), mass: mass, stiffness: stiffness, damping: damping, initialVelocity: initialVelocity)
        }
        let local = index - start
        guard let settle, local > 0 else { return value(local) }
        guard local < settle else { return 1 }
        return value(local) + (1 - value(settle)) * Double(local) / Double(settle)
    }

    public static func springValue(
        at t: Double,
        mass: Double = 1,
        stiffness: Double = 100,
        damping: Double = 10,
        initialVelocity v0: Double = 0
    ) -> Double {
        guard t > 0 else { return 0 }
        let w0 = (stiffness / mass).squareRoot()
        let zeta = damping / (2 * (stiffness * mass).squareRoot())
        // x is the displacement from rest, starting at -1.
        let x0 = -1.0
        let x: Double
        if zeta < 1 {
            let wd = w0 * (1 - zeta * zeta).squareRoot()
            let b = (v0 + zeta * w0 * x0) / wd
            x = exp(-zeta * w0 * t) * (x0 * cos(wd * t) + b * sin(wd * t))
        } else if zeta == 1 {
            x = exp(-w0 * t) * (x0 + (v0 + w0 * x0) * t)
        } else {
            let s = w0 * (zeta * zeta - 1).squareRoot()
            let r1 = -zeta * w0 + s
            let r2 = -zeta * w0 - s
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            x = c1 * exp(r1 * t) + c2 * exp(r2 * t)
        }
        return 1 + x
    }

    // MARK: Time remapping

    /// A frame local to a sequence that starts at `from` and lasts `duration` frames,
    /// or `nil` outside it.
    public func sequence(from start: Int, duration: Int? = nil) -> Frame? {
        let local = index - start
        let length = duration ?? max(frames - start, 0)
        guard local >= 0, local < length else { return nil }
        return Frame(index: local, fps: fps, frames: length)
    }

    /// The same timeline moved `by` frames later, without clipping.
    public func shift(by offset: Int) -> Frame {
        Frame(index: index - offset, fps: fps, frames: frames)
    }

    /// A frame that repeats every `duration` frames.
    public func loop(duration: Int) -> Frame {
        precondition(duration > 0)
        let local = ((index % duration) + duration) % duration
        return Frame(index: local, fps: fps, frames: duration)
    }
}

public enum Easing: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier(Double, Double, Double, Double)

    public func value(_ t: Double) -> Double {
        switch self {
        case .linear: return t
        case .easeIn: return t * t * t
        case .easeOut: return 1 - pow(1 - t, 3)
        case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case let .cubicBezier(x1, y1, x2, y2): return Easing.bezier(t, x1, y1, x2, y2)
        }
    }

    // Fixed iteration count: the result must not depend on a convergence race.
    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func curve(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            t = (lo + hi) / 2
            if curve(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return curve(t, y1, y2)
    }
}
