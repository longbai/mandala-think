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
    var empty = false

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let accent = color?.swatch ?? .mandalaInk
        let fill = accent.opacity(center && !empty ? 0.24 : color == nil ? 0 : 0.16)
        let background = empty ? Color.mandalaPaper : .mandalaCard
        let border = if selected {
            Color.mandalaInk
        } else if color != nil || (center && !empty) {
            accent.opacity(contrast == .increased ? 0.9 : 0.55)
        } else {
            Color.primary.opacity(contrast == .increased ? 0.4 : empty ? 0.15 : 0.09)
        }
        content
            .background {
                shape.fill(fill).background(background, in: shape)
            }
            .overlay {
                shape.strokeBorder(border, lineWidth: selected ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}
