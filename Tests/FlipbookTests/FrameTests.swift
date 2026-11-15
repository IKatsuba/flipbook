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
