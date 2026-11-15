import SwiftUI

extension Frame {
    /// Maps the frame index from `input` to a colour between `output`'s, channel by channel
    /// in gamma-encoded sRGB, as CSS and Core Animation do.
    public func interpolate(
        _ input: [Double],
        _ output: [Color],
        easing: Easing = .linear,
        extrapolate: Extrapolation = .clamp
    ) -> Color {
        let resolved = output.map { $0.resolve(in: EnvironmentValues()) }
        func channel(_ path: KeyPath<Color.Resolved, Float>) -> Float {
            Float(interpolate(input, resolved.map { Double($0[keyPath: path]) }, easing: easing, extrapolate: extrapolate))
        }
        return Color(Color.Resolved(red: channel(\.red), green: channel(\.green), blue: channel(\.blue), opacity: channel(\.opacity)))
    }

    /// An opacity for the current sequence: up from 0 over its first `in` frames,
    /// down to 0 over its last `out` frames, 1 in between.
    public func fade(in rise: Int = 0, out fall: Int = 0, easing: Easing = .linear) -> Double {
        var opacity = 1.0
        if rise > 0 { opacity = min(opacity, interpolate([0, Double(rise)], [0, 1], easing: easing)) }
        if fall > 0 {
            let end = Double(frames - 1)
            opacity = min(opacity, 1 - interpolate([end - Double(fall), end], [0, 1], easing: easing))
        }
        return opacity
    }
}
