import SwiftUI

enum Palette {
    static let background = Color(hex: AppKind.supervisor ? 0x0B1426 : 0x0B0D14)
    static let panel = Color(hex: AppKind.supervisor ? 0x142039 : 0x161824)
    static let muted = Color(hex: AppKind.supervisor ? 0xA4B2C9 : 0x8E95A8)
    static let blue = Color(hex: AppKind.supervisor ? 0x8CB5FF : 0x3B82F6)
    static let green = Color(hex: AppKind.supervisor ? 0x61DAB0 : 0x10B981)
    static let amber = Color(hex: 0xF5C773)
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct Panel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Palette.panel).clipShape(RoundedRectangle(cornerRadius: AppKind.supervisor ? 24 : 16))
            .overlay(RoundedRectangle(cornerRadius: AppKind.supervisor ? 24 : 16).stroke(.white.opacity(0.07)))
    }
}
struct Screen<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16, content: content).padding(16) }.background(Palette.background) }
}
struct PrimaryButton: View {
    let title: String
    var symbol: String = "arrow.right"
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(15) }
            .foregroundStyle(Color(hex: AppKind.supervisor ? 0x0B1426 : 0xFFFFFF))
            .background(enabled ? Palette.blue : Palette.muted.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 14)).disabled(!enabled)
    }
}
struct Badge: View {
    let text: String
    var body: some View { Text(text.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption.bold()).foregroundStyle(Palette.green).padding(.horizontal, 10).padding(.vertical, 6).background(Palette.green.opacity(0.12)).clipShape(Capsule()) }
}
struct ShiftSummary: View {
    let shift: Row
    var body: some View {
        Panel {
            HStack { Text(shift.shiftTitle).font(.headline); Spacer(); Badge(text: shift.text("status", fallback: "Assigned")) }
            Label(shift.text("venue", fallback: shift.text("location")), systemImage: "mappin.and.ellipse").foregroundStyle(Palette.muted)
            Label(shift.timing, systemImage: "calendar").font(.subheadline).foregroundStyle(Palette.muted)
            if !shift.text("role").isEmpty { Text(shift.text("role")).font(.subheadline).foregroundStyle(Palette.blue) }
        }
    }
}
struct Notice: View {
    let text: String
    var body: some View { Text(text).font(.subheadline).foregroundStyle(Palette.amber).frame(maxWidth: .infinity, alignment: .leading).padding().background(Palette.amber.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12)) }
}
struct LoadingRows: View {
    let empty: Bool
    let busy: Bool
    var body: some View { if busy { ProgressView().frame(maxWidth: .infinity).padding() } else if empty { ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Pull down to refresh.")) } }
}
struct StatGrid: View {
    let values: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(values.indices, id: \.self) { index in
                Panel { Text(values[index].1).font(.largeTitle.bold()).foregroundStyle(Palette.blue); Text(values[index].0).font(.caption).foregroundStyle(Palette.muted) }
            }
        }
    }
}
