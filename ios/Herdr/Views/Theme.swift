import SwiftUI

enum Theme {
    static let background = Color(red: 17/255, green: 20/255, blue: 19/255)
    static let surface = Color(red: 28/255, green: 33/255, blue: 30/255)
    static let mint = Color(red: 181/255, green: 228/255, blue: 201/255)
    static let secondary = Color(red: 170/255, green: 181/255, blue: 174/255)
    static let attention = Color(red: 245/255, green: 193/255, blue: 91/255)
    static func status(_ agent: Agent) -> Color { agent.stale ? secondary : agent.needsAttention ? attention : ["working", "done", "idle"].contains(agent.status) ? mint : secondary }
}
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 48).padding(.horizontal, 12)
            .foregroundStyle(Theme.background).background(Theme.mint.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 12)).opacity(isEnabled ? 1 : 0.45)
    }
}
struct StatusLabel: View {
    let agent: Agent
    var body: some View { Label(agent.statusLabel, systemImage: agent.stale ? "clock" : agent.needsAttention ? "exclamationmark.circle" : agent.status == "working" ? "circle.fill" : "checkmark.circle").font(.subheadline).foregroundStyle(Theme.status(agent)) }
}
struct Notice: View {
    let text: String
    var symbol = "wifi.exclamationmark"
    var body: some View { Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(Theme.attention).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .combine) }
}
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View { content.background(Theme.background).toolbarBackground(Theme.background, for: .navigationBar, .tabBar).toolbarBackground(.visible, for: .tabBar) }
}
extension View { func herdrScreen() -> some View { modifier(ScreenBackground()) } }
