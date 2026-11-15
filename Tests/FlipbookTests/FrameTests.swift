import SwiftUI
import Testing
@testable import Flipbook

@Test func interpolateClampsAndEases() {
    let f = { Frame(index: $0, fps: 60, frames: 100) }
    #expect(f(0).interpolate([10, 20], [0, 1]) == 0)
    #expect(f(15).interpolate([10, 20], [0, 1]) == 0.5)
    #expect(f(99).interpolate([10, 20], [0, 1]) == 1)
    #expect(f(30).interpolate([10, 20], [0, 1], extrapolate: .extend) == 2)
    #expect(f(25).interpolate([0, 10, 20, 30], [0, 1, 1, 0]) == 0.5)
    #expect(f(15).interpolate([10, 20], [0, 1], easing: .easeOut) == 0.875)
}

@Test func springStartsAtZeroAndSettlesAtOne() {
    #expect(Frame(index: 0, fps: 60, frames: 600).spring() == 0)
    #expect(Frame(index: 5, fps: 60, frames: 600).spring(from: 10) == 0)
    for damping in [5.0, 20.0, 40.0] {
        let settled = Frame(index: 599, fps: 60, frames: 600).spring(damping: damping)
        #expect(abs(settled - 1) < 1e-3)
    }
    // Underdamped springs overshoot.
    let peak = (0..<120).map { Frame(index: $0, fps: 60, frames: 120).spring(damping: 5) }.max()!
    #expect(peak > 1.1)
}

@Test func springMatchesFixedStepIntegration() {
    // Semi-implicit Euler at 1/6000 s as an independent check of the closed form.
    for damping in [6.0, 20.0, 30.0] {
        var x = 0.0, v = 0.0
        let dt = 1.0 / 6000
        for step in 1...6000 {
            v += (100 * (1 - x) - damping * v) * dt
            x += v * dt
            if step % 600 == 0 {
                let exact = Frame.springValue(at: Double(step) * dt, damping: damping)
                #expect(abs(exact - x) < 2e-3)
            }
        }
    }
}

@Test func sequenceAndLoop() {
    let f = Frame(index: 45, fps: 30, frames: 90)
    #expect(f.sequence(from: 30, duration: 30) == Frame(index: 15, fps: 30, frames: 30))
    #expect(f.sequence(from: 50, duration: 30) == nil)
    #expect(f.sequence(from: 0, duration: 45) == nil)
    #expect(f.sequence(from: 40)?.frames == 50)
    #expect(f.loop(duration: 20).index == 5)
    #expect(f.shift(by: 40).index == 5)
    #expect(f.time == 1.5)
}

@Test func settledSpringArrivesAndStays() {
    let f = { Frame(index: $0, fps: 60, frames: 600) }
    #expect(f(10).spring(from: 10, settle: 40) == 0)
    #expect(f(50).spring(from: 10, settle: 40) == 1)
    #expect(f(400).spring(from: 10, settle: 40) == 1)
    // Close to the free spring on the way there.
    #expect(abs(f(30).spring(from: 10, settle: 40) - f(30).spring(from: 10)) < 0.02)
}

@Test func snapRoundsToThePixelGrid() {
    #expect(Frame(index: 0, fps: 60, frames: 1).snap(10.4) == 10)
    #expect(Frame(index: 0, fps: 60, frames: 1, scale: 2).snap(10.4) == 10.5)
    #expect(Frame(index: 0, fps: 60, frames: 1, scale: 2).snap(-0.2) == 0)
    // The scale survives time remapping.
    let frame = Frame(index: 30, fps: 60, frames: 90, scale: 3)
    #expect(frame.sequence(from: 10, duration: 40)?.scale == 3)
    #expect(frame.loop(duration: 7).scale == 3)
    #expect(frame.shift(by: 5).scale == 3)
}

@Test func typedGrowsOneCharacterAtATime() {
    let f = { Frame(index: $0, fps: 60, frames: 100) }
    #expect(f(0).typed("héllo 👋", from: 10) == "")
    #expect(f(10).typed("héllo 👋", from: 10) == "")
    #expect(f(12).typed("héllo 👋", from: 10) == "h")
    #expect(f(14).typed("héllo 👋", from: 10) == "hé")
    #expect(f(99).typed("héllo 👋", from: 10) == "héllo 👋")
    #expect(f(3).typed("abc", per: 0.5) == "abc")
}

@Test func coloursInterpolatePerChannel() {
    let grey = Frame(index: 5, fps: 60, frames: 11).interpolate([0, 10], [.black, .white])
    let resolved = grey.resolve(in: EnvironmentValues())
    #expect(abs(resolved.red - 0.5) < 0.01 && abs(resolved.green - 0.5) < 0.01 && abs(resolved.blue - 0.5) < 0.01)
    #expect(resolved.opacity == 1)
    let clear = Frame(index: 20, fps: 60, frames: 21).interpolate([0, 10], [Color.red, Color.red.opacity(0)])
    #expect(clear.resolve(in: EnvironmentValues()).opacity == 0)
}

@Test func fadeRisesHoldsAndFalls() {
    let f = { Frame(index: $0, fps: 60, frames: 100) }
    #expect(f(0).fade(in: 10, out: 20) == 0)
    #expect(f(5).fade(in: 10, out: 20) == 0.5)
    #expect(f(50).fade(in: 10, out: 20) == 1)
    #expect(f(89).fade(in: 10, out: 20) == 0.5)
    #expect(f(99).fade(in: 10, out: 20) == 0)
    #expect(f(0).fade() == 1)
    // Inside a sequence it follows the sequence's own length.
    #expect(f(49).sequence(from: 10, duration: 40)?.fade(out: 10) == 0)
}
