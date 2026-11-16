import Flipbook
import SwiftUI

// The repository's social preview, at twice GitHub's 1280×640. It shares the promo's look:
// Kit.swift here is a link to the promo's.
//
//   flipbook still Examples/social --out docs/images/social.png

/// The repository's social preview: 1280×640, the book, the name and what it does.
struct SocialCard: View {
    var body: some View {
        ZStack {
            Look.paper
            RoundedRectangle(cornerRadius: 6).strokeBorder(Look.faint, lineWidth: 1.5).padding(28)
            HStack(spacing: 64) {
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Page(phase: Double(index + 1) / 5, size: CGSize(width: 190, height: 240))
                            .rotationEffect(.degrees(Double(index - 3) * 7), anchor: .bottomLeading)
                            .offset(x: CGFloat(index - 3) * 16)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flipbook").font(Look.serif(132, .black)).tracking(-3).foregroundStyle(Look.ink)
                    Text("Videos from SwiftUI views.").font(Look.mono(34)).foregroundStyle(Look.dim)
                    Text("Every frame a pure function of its number.").font(Look.serif(30, .regular)).foregroundStyle(Look.accent).padding(.top, 14)
                }
            }
            .padding(.leading, 30)
        }
    }
}

let composition = Composition(width: 1280, height: 640, frames: 1, scale: 2) { _ in
    SocialCard()
}

try await composition.run()
