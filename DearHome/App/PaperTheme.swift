import SwiftUI

struct PaperPalette {
    var paper: Color
    var ink: Color
    var secondary: Color
    var rule: Color
    var card: Color
    var terracotta: Color
    var moss: Color

    static func resolve(_ scheme: ColorScheme) -> PaperPalette {
        if scheme == .dark {
            return PaperPalette(
                paper: Color(red: 0.11, green: 0.10, blue: 0.09),
                ink: Color(red: 0.95, green: 0.93, blue: 0.88),
                secondary: Color(red: 0.73, green: 0.68, blue: 0.60),
                rule: Color(red: 0.30, green: 0.27, blue: 0.23),
                card: Color(red: 0.16, green: 0.15, blue: 0.13),
                terracotta: Color(red: 0.86, green: 0.52, blue: 0.38),
                moss: Color(red: 0.62, green: 0.72, blue: 0.58)
            )
        }
        return PaperPalette(
            paper: Color(red: 0.965, green: 0.941, blue: 0.894),
            ink: Color(red: 0.145, green: 0.165, blue: 0.155),
            secondary: Color(red: 0.39, green: 0.40, blue: 0.36),
            rule: Color(red: 0.78, green: 0.73, blue: 0.64),
            card: Color(red: 0.992, green: 0.976, blue: 0.949),
            terracotta: Color(red: 0.62, green: 0.30, blue: 0.20),
            moss: Color(red: 0.28, green: 0.40, blue: 0.32)
        )
    }
}

struct NotebookBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PaperPalette.resolve(scheme).paper.ignoresSafeArea())
    }
}

extension View {
    func notebookBackground() -> some View { modifier(NotebookBackground()) }
}

struct RosetteMark: View {
    var color: Color
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.34
            var petals = Path()
            for index in 0..<8 {
                let angle = (Double(index) / 8) * Double.pi * 2
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                                    y: center.y + CGFloat(sin(angle)) * radius)
                petals.addEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            }
            petals.addEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
            context.fill(petals, with: .color(color))
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
