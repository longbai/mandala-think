import SwiftUI
import MandalaCore

extension CellColor {
    var swatch: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

struct CellColorMenu: View {
    let color: CellColor?
    let select: (CellColor?) -> Void
    @Environment(\.words) private var words

    var body: some View {
        Menu {
            Picker(words("cell.color"), selection: Binding(get: { color }, set: select)) {
                Text(words("color.default")).tag(nil as CellColor?)
                ForEach(CellColor.allCases, id: \.self) { choice in
                    Text(words("color." + choice.rawValue)).tag(Optional(choice))
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: color == nil ? "paintpalette" : "circle.fill")
                    .foregroundStyle(color?.swatch ?? Color.mandalaInk)
                Text(words(color.map { "color." + $0.rawValue } ?? "color.default"))
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(words("cell.color"))
        .accessibilityValue(words(color.map { "color." + $0.rawValue } ?? "color.default"))
        .accessibilityIdentifier("cell-color")
    }
}

struct CellSurface: ViewModifier {
    let color: CellColor?
    let center: Bool
    let selected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let background = color?.swatch.opacity(0.23) ?? (center ? Color.mandalaInk.opacity(0.15) : .mandalaCard)
        content
            .background(background, in: shape)
            .overlay {
                shape.strokeBorder(color?.swatch.opacity(0.85) ?? Color.mandalaInk.opacity(0.12),
                                   lineWidth: color == nil ? 1 : 3)
                    .allowsHitTesting(false)
            }
            .overlay {
                if selected {
                    shape.inset(by: color == nil ? 0 : 3)
                        .strokeBorder(Color.mandalaInk, lineWidth: 2).allowsHitTesting(false)
                }
            }
    }
}
