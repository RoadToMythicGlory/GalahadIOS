import SwiftUI

/// Galahad dark design system: near-black background, elevated cards with
/// hairline strokes, electric-blue accent, green/orange/red status colors.
enum Theme {
    static let background = Color(red: 0.043, green: 0.051, blue: 0.067)
    static let card = Color(red: 0.086, green: 0.098, blue: 0.125)
    static let cardElevated = Color(red: 0.118, green: 0.133, blue: 0.169)
    static let stroke = Color.white.opacity(0.07)
    static let accent = Color(red: 0.259, green: 0.549, blue: 1.0)
    static let good = Color(red: 0.298, green: 0.851, blue: 0.529)
    static let warn = Color(red: 1.0, green: 0.686, blue: 0.259)
    static let bad = Color(red: 1.0, green: 0.322, blue: 0.322)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

struct CardStyle: ViewModifier {
    var selected = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Theme.cardElevated : Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 1.5 : 1)
                    )
            )
    }
}

extension View {
    func card(selected: Bool = false) -> some View {
        modifier(CardStyle(selected: selected))
    }
}

/// Screen header used across tabs: logo on the left, centered title.
struct ScreenHeader: View {
    let title: String

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Image("Logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
            }
        }
        .padding(.top, 4)
    }
}

/// Small grey section caption above cards ("Destination", "Preset", ...).
struct SectionCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 2)
    }
}

/// Colored status dot + label, e.g. "Good ●".
struct StatusTag: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }
}

/// Minimal line chart with gradient fill for bitrate history.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 0.1)
            let count = max(values.count - 1, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(count),
                    y: geo.size.height * (1 - 0.9 * CGFloat(value / maxValue))
                )
            }
            if points.count > 1 {
                Path { p in
                    p.addLines(points)
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in
                    p.addLines(points)
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.28), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }
}
